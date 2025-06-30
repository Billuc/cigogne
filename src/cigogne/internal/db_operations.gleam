import cigogne/internal/database
import cigogne/internal/utils
import cigogne/types
import gleam/bool
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/string
import pog

const check_table_exist = "SELECT table_name, table_schema 
    FROM information_schema.tables 
    WHERE table_type = 'BASE TABLE' 
      AND table_name = $1
      AND table_schema = $2;"

const create_migrations_table = "CREATE TABLE IF NOT EXISTS $1(
    id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(255) NOT NULL,
    sha256 VARCHAR(64) NOT NULL,
    createdAt TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    appliedAt TIMESTAMP NOT NULL DEFAULT NOW()
);"

const query_insert_migration = "INSERT INTO $1(createdAt, name, sha256) VALUES ($2, $3, $4);"

const query_drop_migration = "DELETE FROM $1 WHERE name = $2 AND createdAt = $3;"

const query_applied_migrations = "SELECT createdAt, name, sha256 FROM $1 ORDER BY appliedAt ASC;"

pub fn migrations_table_exists(
  data: types.DatabaseData,
) -> Result(Bool, types.MigrateError) {
  pog.query(check_table_exist)
  |> pog.parameter(pog.text(data.migrations_table_name))
  |> pog.parameter(pog.text(data.schema))
  |> pog.returning({
    use name <- decode.field(0, decode.string)
    use schema <- decode.field(1, decode.string)
    decode.success(#(name, schema))
  })
  |> database.execute(data.connection)
  |> result.map(fn(tables) { !list.is_empty(tables) })
}

pub fn apply_cigogne_zero(
  data: types.DatabaseData,
) -> Result(Nil, types.MigrateError) {
  use exists <- result.try(migrations_table_exists(data))
  use <- bool.guard(exists, Ok(Nil))

  create_zero_migration(
    "CreateMigrationTable",
    [
      create_migrations_table
      |> string.replace("$1", data.migrations_table_name),
    ],
    [],
  )
  |> apply_migration(data, _)
}

pub fn apply_migration(
  data: types.DatabaseData,
  migration: types.Migration,
) -> Result(Nil, types.MigrateError) {
  let queries =
    list.map(migration.queries_up, pog.query)
    |> list.append([insert_migration_query(data, migration)])

  database.execute_batch(data.connection, queries)
}

pub fn rollback_migration(
  data: types.DatabaseData,
  migration: types.Migration,
) -> Result(Nil, types.MigrateError) {
  let queries =
    list.map(migration.queries_down, pog.query)
    |> list.append([drop_migration_query(data, migration)])

  database.execute_batch(data.connection, queries)
}

pub fn insert_migration_query(
  data: types.DatabaseData,
  migration: types.Migration,
) -> pog.Query(Nil) {
  pog.query(query_insert_migration)
  |> pog.parameter(pog.text(data.migrations_table_name))
  |> pog.parameter(pog.timestamp(
    migration.timestamp |> utils.tempo_to_pog_timestamp,
  ))
  |> pog.parameter(pog.text(migration.name))
  |> pog.parameter(pog.text(migration.sha256))
}

pub fn drop_migration_query(
  data: types.DatabaseData,
  migration: types.Migration,
) -> pog.Query(Nil) {
  pog.query(query_drop_migration)
  |> pog.parameter(pog.text(data.migrations_table_name))
  |> pog.parameter(pog.text(migration.name))
  |> pog.parameter(pog.timestamp(
    migration.timestamp |> utils.tempo_to_pog_timestamp,
  ))
}

pub fn get_applied_migrations(
  data: types.DatabaseData,
) -> Result(List(types.Migration), types.MigrateError) {
  pog.query(query_applied_migrations)
  |> pog.parameter(pog.text(data.migrations_table_name))
  |> pog.returning({
    use timestamp <- decode.field(0, pog.timestamp_decoder())
    use name <- decode.field(1, decode.string)
    use hash <- decode.field(2, decode.string)
    decode.success(#(timestamp, name, hash))
  })
  |> database.execute(data.connection)
  |> result.then(fn(returned) {
    case returned {
      [] -> Error(types.NoResultError)
      _ as applied -> applied |> list.try_map(build_migration_data)
    }
  })
}

fn build_migration_data(
  data: #(pog.Timestamp, String, String),
) -> Result(types.Migration, types.MigrateError) {
  case utils.pog_to_tempo_timestamp(data.0) {
    Error(_) ->
      Error(types.DateParseError(utils.pog_timestamp_to_string(data.0)))
    Ok(timestamp) -> Ok(types.Migration("", timestamp, data.1, [], [], data.2))
  }
}

/// Create a "zero" migration that should be applied before the user's migrations
pub fn create_zero_migration(
  name: String,
  queries_up: List(String),
  queries_down: List(String),
) -> types.Migration {
  types.Migration(
    "",
    utils.tempo_epoch(),
    name,
    queries_up,
    queries_down,
    utils.make_sha256(
      queries_up |> string.join(";") <> queries_down |> string.join(";"),
    ),
  )
}
