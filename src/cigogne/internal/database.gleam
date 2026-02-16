import cigogne/config
import cigogne/migration
import envoy
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/time/timestamp
import pog

const cigogne_process_name = "cigogne"

pub type DatabaseData {
  DatabaseData(
    connection: pog.Connection,
    migrations_table: String,
    db_schema: String,
  )
}

pub type DatabaseError {
  EnvVarUnset(name: String)
  IncorrectConnectionString(conn_string: String)
  ActorStartError(error: actor.StartError)
  PogQueryError(error: pog.QueryError)
  PogTransactionError(error: pog.TransactionError(DatabaseError))
}

const check_table_exist = "SELECT table_name, table_schema
    FROM information_schema.tables
    WHERE table_type = 'BASE TABLE'
      AND table_name = $1
      AND table_schema = $2;"

fn create_migrations_table(schema: String, migrations_table: String) -> String {
  "CREATE TABLE IF NOT EXISTS " <> schema <> "." <> migrations_table <> "(
    id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(255) NOT NULL,
    sha256 VARCHAR(64) NOT NULL,
    createdAt TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    appliedAt TIMESTAMP NOT NULL DEFAULT NOW()
);"
}

fn query_insert_migration(schema: String, migrations_table: String) -> String {
  "INSERT INTO "
  <> schema
  <> "."
  <> migrations_table
  <> "(createdAt, name, sha256) VALUES ($1, $2, $3);"
}

fn query_drop_migration(schema: String, migrations_table: String) -> String {
  "DELETE FROM "
  <> schema
  <> "."
  <> migrations_table
  <> " WHERE name = $1 AND createdAt = $2;"
}

fn query_applied_migrations(schema: String, migrations_table: String) -> String {
  "SELECT createdAt, name, sha256 FROM "
  <> schema
  <> "."
  <> migrations_table
  <> " ORDER BY appliedAt ASC;"
}

pub fn init(config: config.Config) -> Result(DatabaseData, DatabaseError) {
  use connection <- result.try(connect(config.database))
  Ok(DatabaseData(
    connection:,
    migrations_table: config.migration_table.table
      |> option.unwrap("_migrations"),
    db_schema: config.migration_table.schema |> option.unwrap("public"),
  ))
}

fn connect(
  config: config.DatabaseConfig,
) -> Result(pog.Connection, DatabaseError) {
  case config {
    config.EnvVarConfig -> connection_from_env()
    config.UrlDbConfig(url:) -> connection_from_url(url)
    config.ConnectionDbConfig(connection:) -> Ok(connection)
    config.DetailedDbConfig(host:, user:, password:, port:, name:) ->
      connection_from_config(host:, user:, password:, name:, port:)
  }
}

fn connection_from_env() -> Result(pog.Connection, DatabaseError) {
  case envoy.get("DATABASE_URL") {
    Ok(url) -> connection_from_url(url)
    Error(_) ->
      connection_from_config(
        host: envoy.get("PGHOST") |> option.from_result,
        user: envoy.get("PGUSER") |> option.from_result,
        password: envoy.get("PGPASSWORD") |> option.from_result,
        name: envoy.get("PGDATABASE") |> option.from_result,
        port: envoy.get("PGPORT") |> result.try(int.parse) |> option.from_result,
      )
  }
}

fn apply_if_some(
  input: a,
  value: option.Option(b),
  apply_fn: fn(a, b) -> a,
) -> a {
  case value {
    option.Some(v) -> apply_fn(input, v)
    option.None -> input
  }
}

fn connection_from_config(
  host host: option.Option(String),
  user user: option.Option(String),
  password password: option.Option(String),
  name name: option.Option(String),
  port port: option.Option(Int),
) -> Result(pog.Connection, DatabaseError) {
  let procname = process.new_name(cigogne_process_name)
  let config =
    pog.default_config(procname)
    |> apply_if_some(user, pog.user)
    |> pog.password(password)
    |> apply_if_some(host, pog.host)
    |> apply_if_some(port, pog.port)
    |> apply_if_some(name, pog.database)
  pog.start(config)
  |> result.map_error(ActorStartError)
  |> result.map(fn(actor) { actor.data })
}

fn connection_from_url(url: String) -> Result(pog.Connection, DatabaseError) {
  let db_process_name = process.new_name(cigogne_process_name)

  pog.url_config(db_process_name, url)
  |> result.replace_error(IncorrectConnectionString(url))
  |> result.try(fn(c) { pog.start(c) |> result.map_error(ActorStartError) })
  |> result.map(fn(actor) { actor.data })
}

pub fn migrations_table_exists(
  data: DatabaseData,
) -> Result(Bool, DatabaseError) {
  let tables_query =
    pog.query(check_table_exist)
    |> pog.parameter(pog.text(data.migrations_table))
    |> pog.parameter(pog.text(data.db_schema))
    |> pog.returning({
      use name <- decode.field(0, decode.string)
      use schema <- decode.field(1, decode.string)
      decode.success(#(name, schema))
    })

  let tables_result =
    tables_query
    |> pog.execute(data.connection)

  case tables_result {
    Ok(tables) -> Ok(tables.count > 0)
    Error(db_err) -> Error(PogQueryError(db_err))
  }
}

pub fn apply_cigogne_zero(data: DatabaseData) -> Result(Nil, DatabaseError) {
  case migrations_table_exists(data) {
    Ok(True) -> Ok(Nil)
    Error(err) -> Error(err)
    Ok(False) -> {
      migration.create_zero_migration(
        "CreateMigrationTable",
        [create_migrations_table(data.db_schema, data.migrations_table)],
        [],
      )
      |> apply_migration(data, _)
    }
  }
}

pub fn apply_migration(
  data: DatabaseData,
  migration: migration.Migration,
) -> Result(Nil, DatabaseError) {
  {
    use transaction <- pog.transaction(data.connection)

    list.try_each(migration.queries_up, fn(q) {
      pog.query(q) |> pog.execute(transaction)
    })
    |> result.try(fn(_) {
      insert_migration_query(data, migration)
      |> pog.execute(transaction)
      |> result.replace(Nil)
    })
    |> result.map_error(PogQueryError)
  }
  |> result.map_error(PogTransactionError)
}

pub fn rollback_migration(
  data: DatabaseData,
  migration: migration.Migration,
) -> Result(Nil, DatabaseError) {
  {
    use transaction <- pog.transaction(data.connection)

    list.try_each(migration.queries_down, fn(q) {
      pog.query(q) |> pog.execute(transaction)
    })
    |> result.try(fn(_) {
      drop_migration_query(data, migration)
      |> pog.execute(transaction)
      |> result.replace(Nil)
    })
    |> result.map_error(PogQueryError)
  }
  |> result.map_error(PogTransactionError)
}

pub fn apply_migration_no_transaction(
  data: DatabaseData,
  migration: migration.Migration,
) -> Result(Nil, DatabaseError) {
  list.try_each(migration.queries_up, fn(q) {
    pog.query(q) |> pog.execute(data.connection)
  })
  |> result.try(fn(_) {
    insert_migration_query(data, migration)
    |> pog.execute(data.connection)
    |> result.replace(Nil)
  })
  |> result.map_error(PogQueryError)
}

pub fn rollback_migration_no_transaction(
  data: DatabaseData,
  migration: migration.Migration,
) -> Result(Nil, DatabaseError) {
  list.try_each(migration.queries_down, fn(q) {
    pog.query(q) |> pog.execute(data.connection)
  })
  |> result.try(fn(_) {
    drop_migration_query(data, migration)
    |> pog.execute(data.connection)
    |> result.replace(Nil)
  })
  |> result.map_error(PogQueryError)
}

pub fn transaction(
  data: DatabaseData,
  callback: fn(pog.Connection) -> Result(a, DatabaseError),
) {
  {
    use transaction <- pog.transaction(data.connection)
    callback(transaction)
  }
  |> result.map_error(PogTransactionError)
}

fn insert_migration_query(
  data: DatabaseData,
  migration: migration.Migration,
) -> pog.Query(Nil) {
  query_insert_migration(data.db_schema, data.migrations_table)
  |> pog.query()
  |> pog.parameter(pog.timestamp(migration.timestamp))
  |> pog.parameter(pog.text(migration.name))
  |> pog.parameter(pog.text(migration.sha256))
}

fn drop_migration_query(
  data: DatabaseData,
  migration: migration.Migration,
) -> pog.Query(Nil) {
  query_drop_migration(data.db_schema, data.migrations_table)
  |> pog.query()
  |> pog.parameter(pog.text(migration.name))
  |> pog.parameter(pog.timestamp(migration.timestamp))
}

pub fn get_applied_migrations(
  data: DatabaseData,
) -> Result(List(migration.Migration), DatabaseError) {
  query_applied_migrations(data.db_schema, data.migrations_table)
  |> pog.query()
  |> pog.returning({
    use timestamp <- decode.field(0, pog.timestamp_decoder())
    use name <- decode.field(1, decode.string)
    use hash <- decode.field(2, decode.string)
    decode.success(#(timestamp, name, hash))
  })
  |> pog.execute(data.connection)
  |> result.map_error(PogQueryError)
  |> result.map(fn(returned) { returned.rows |> list.map(db_data_to_migration) })
}

fn db_data_to_migration(
  data: #(timestamp.Timestamp, String, String),
) -> migration.Migration {
  migration.Migration("", data.0, data.1, [], [], data.2)
}

pub fn get_error_message(error: DatabaseError) -> String {
  case error {
    ActorStartError(error:) -> describe_actor_start_error(error)
    EnvVarUnset(name:) -> "Environment variable " <> name <> " is not set"
    IncorrectConnectionString(conn_string:) ->
      "Connection string " <> conn_string <> " is invalid"
    PogQueryError(error:) -> describe_query_error(error)
    PogTransactionError(error:) -> describe_transaction_error(error)
  }
}

fn describe_actor_start_error(error: actor.StartError) -> String {
  case error {
    actor.InitExited(_) -> "pog actor initialization exited"
    actor.InitFailed(message) ->
      "pog actor initialization failed with message " <> message
    actor.InitTimeout -> "Timeout on pog actor initialization"
  }
}

fn describe_query_error(error: pog.QueryError) -> String {
  case error {
    pog.ConnectionUnavailable -> "CONNECTION UNAVAILABLE"
    pog.ConstraintViolated(message, _constraint, _detail) -> message
    pog.PostgresqlError(_code, _name, message) ->
      "Postgresql error: " <> message
    pog.UnexpectedArgumentCount(expected, got) ->
      "Expected "
      <> int.to_string(expected)
      <> " arguments, got "
      <> int.to_string(got)
      <> " !"
    pog.UnexpectedArgumentType(expected, got) ->
      "Expected argument of type " <> expected <> ", got " <> got <> " !"
    pog.UnexpectedResultType(errs) ->
      "Unexpected result types !\n  "
      <> list.map(errs, describe_decode_error) |> string.join("\n  ")
    pog.QueryTimeout -> "Query Timeout"
  }
}

fn describe_transaction_error(
  error: pog.TransactionError(DatabaseError),
) -> String {
  case error {
    pog.TransactionQueryError(suberror) -> describe_query_error(suberror)
    pog.TransactionRolledBack(error) ->
      "Transaction rolled back : " <> get_error_message(error)
  }
}

fn describe_decode_error(error: decode.DecodeError) -> String {
  "Expecting : "
  <> error.expected
  <> ", Got : "
  <> error.found
  <> " [at "
  <> error.path |> string.join("/")
  <> "]"
}
