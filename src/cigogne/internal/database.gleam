import cigogne/internal/migrations_utils
import cigogne/internal/utils
import cigogne/types
import envoy
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/list
import gleam/option
import gleam/result
import gleam/time/timestamp
import pog
import shellout

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

pub type DatabaseData {
  DatabaseData(
    connection: pog.Connection,
    migrations_table: String,
    db_schema: String,
    db_url: option.Option(String),
  )
}

pub fn init(
  config: types.ConnectionConfig,
) -> Result(DatabaseData, types.MigrateError) {
  use #(connection, db_url) <- result.try(connect(config.connection))
  Ok(DatabaseData(
    connection:,
    migrations_table: config.migrations_table,
    db_schema: config.db_schema,
    db_url:,
  ))
}

fn connect(
  config: types.PogConnectionConfig,
) -> Result(#(pog.Connection, option.Option(String)), types.MigrateError) {
  case config {
    types.PogConnection(connection:) -> Ok(#(connection, option.None))
    types.EnvVar -> {
      envoy.get("DATABASE_URL")
      |> result.replace_error(types.EnvVarError("DATABASE_URL"))
      |> result.try(fn(url) {
        connection_from_url(url)
        |> result.map(fn(c) { #(c, option.Some(url)) })
      })
    }
    types.PogConfig(config:) ->
      config
      |> pog.start
      |> result.map_error(types.ActorStartError)
      |> result.map(fn(actor) { #(actor.data, option.None) })
    types.ConnectionString(url:) -> {
      connection_from_url(url)
      |> result.map(fn(c) { #(c, option.Some(url)) })
    }
  }
}

fn connection_from_url(
  url: String,
) -> Result(pog.Connection, types.MigrateError) {
  let db_process_name = process.new_name("cigogne")

  pog.url_config(db_process_name, url)
  |> result.replace_error(types.UrlError(url))
  |> result.try(fn(c) {
    pog.start(c) |> result.map_error(types.ActorStartError)
  })
  |> result.map(fn(actor) { actor.data })
}

pub fn migrations_table_exists(
  data: DatabaseData,
) -> Result(Bool, types.MigrateError) {
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
    Error(db_err) -> Error(types.PGOQueryError(db_err))
  }
}

pub fn apply_cigogne_zero(data: DatabaseData) -> Result(Nil, types.MigrateError) {
  case migrations_table_exists(data) {
    Ok(True) -> Ok(Nil)
    Error(err) -> Error(err)
    Ok(False) -> {
      migrations_utils.create_zero_migration(
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
  migration: types.Migration,
) -> Result(Nil, types.MigrateError) {
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
    |> result.map_error(utils.describe_query_error)
  }
  |> result.map_error(types.PGOTransactionError)
}

pub fn rollback_migration(
  data: DatabaseData,
  migration: types.Migration,
) -> Result(Nil, types.MigrateError) {
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
    |> result.map_error(utils.describe_query_error)
  }
  |> result.map_error(types.PGOTransactionError)
}

fn insert_migration_query(
  data: DatabaseData,
  migration: types.Migration,
) -> pog.Query(Nil) {
  query_insert_migration(data.db_schema, data.migrations_table)
  |> pog.query()
  |> pog.parameter(pog.timestamp(migration.timestamp))
  |> pog.parameter(pog.text(migration.name))
  |> pog.parameter(pog.text(migration.sha256))
}

fn drop_migration_query(
  data: DatabaseData,
  migration: types.Migration,
) -> pog.Query(Nil) {
  query_drop_migration(data.db_schema, data.migrations_table)
  |> pog.query()
  |> pog.parameter(pog.text(migration.name))
  |> pog.parameter(pog.timestamp(migration.timestamp))
}

pub fn get_applied_migrations(
  data: DatabaseData,
) -> Result(List(types.Migration), types.MigrateError) {
  query_applied_migrations(data.db_schema, data.migrations_table)
  |> pog.query()
  |> pog.returning({
    use timestamp <- decode.field(0, pog.timestamp_decoder())
    use name <- decode.field(1, decode.string)
    use hash <- decode.field(2, decode.string)
    decode.success(#(timestamp, name, hash))
  })
  |> pog.execute(data.connection)
  |> result.map_error(types.PGOQueryError)
  |> result.try(fn(returned) {
    case returned.rows {
      [] -> Error(types.NoResultError)
      _ as applied -> applied |> list.map(build_migration_data) |> Ok
    }
  })
}

fn build_migration_data(
  data: #(timestamp.Timestamp, String, String),
) -> types.Migration {
  types.Migration("", data.0, data.1, [], [], data.2)
}

pub fn get_schema(data: DatabaseData) -> Result(String, types.MigrateError) {
  case data.db_url {
    option.None -> Error(types.UrlError("None"))
    option.Some(url) ->
      shellout.command(
        "psql",
        [url, "-c", "\\d " <> data.db_schema <> ".*"],
        ".",
        [],
      )
      |> result.map_error(fn(err) { types.SchemaQueryError(err.1) })
  }
}
