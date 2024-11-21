import envoy
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import pog
import stork/exec
import stork/files
import stork/types

const migration_zero = types.Migration(
  "",
  0,
  "CreateMigrationsTable",
  [
    "CREATE TABLE IF NOT EXISTS _migrations(
    id INT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    appliedAt TIMESTAMP NOT NULL DEFAULT NOW()
);",
  ],
  [],
)

const query_last_applied_migration = "SELECT id, name FROM _migrations ORDER BY appliedAt DESC LIMIT 1;"

pub fn migrate_up() -> Result(Nil, types.MigrateError) {
  use conn <- result.try(db_connect())
  use _ <- result.try(
    exec.exec_migration_up(conn, migration_zero)
    |> result.map_error(types.PGOTransactionError),
  )
  use last <- result.try(get_last_applied_migration(conn))

  use migrations <- result.try(files.get_migrations())

  use migration <- result.try(
    list.find(migrations, fn(m) { m.number == last.0 + 1 })
    |> result.replace_error(types.MigrationNotFoundError(last.0 + 1)),
  )
  use _ <- result.try(
    exec.exec_migration_up(conn, migration)
    |> result.map_error(types.PGOTransactionError),
  )
  use url <- result.try(get_db_url())
  use schema <- result.try(
    exec.get_schema(url) |> result.map_error(types.SchemaQueryError),
  )
  files.write_schema_file(schema)
}

pub fn migrate_down() -> Result(Nil, types.MigrateError) {
  use conn <- result.try(db_connect())
  use _ <- result.try(
    exec.exec_migration_up(conn, migration_zero)
    |> result.map_error(types.PGOTransactionError),
  )
  use last <- result.try(get_last_applied_migration(conn))

  use migrations <- result.try(files.get_migrations())

  use migration <- result.try(
    list.find(migrations, fn(m) { m.number == last.0 })
    |> result.replace_error(types.MigrationNotFoundError(last.0)),
  )
  use _ <- result.try(
    exec.exec_migration_down(conn, migration)
    |> result.map_error(types.PGOTransactionError),
  )
  use url <- result.try(get_db_url())
  use schema <- result.try(
    exec.get_schema(url) |> result.map_error(types.SchemaQueryError),
  )
  files.write_schema_file(schema)
}

pub fn migrate_to(number: Int) -> Result(Nil, types.MigrateError) {
  use conn <- result.try(db_connect())
  use _ <- result.try(
    exec.exec_migration_up(conn, migration_zero)
    |> result.map_error(types.PGOTransactionError),
  )
  use last <- result.try(get_last_applied_migration(conn))

  use migrations <- result.try(files.get_migrations())
  let up = number > last.0
  use to_apply <- result.try(
    list.range(last.0, number)
    |> list.try_map(find_migration(migrations, _)),
  )

  use _ <- result.try(
    list.try_each(to_apply, fn(migration) {
      case up {
        True -> exec.exec_migration_up(conn, migration)
        False -> exec.exec_migration_down(conn, migration)
      }
      |> result.map_error(types.PGOTransactionError)
    }),
  )
  use url <- result.try(get_db_url())
  use schema <- result.try(
    exec.get_schema(url) |> result.map_error(types.SchemaQueryError),
  )
  files.write_schema_file(schema)
}

pub fn show() -> Result(Nil, types.MigrateError) {
  use conn <- result.try(db_connect())
  use _ <- result.try(
    exec.exec_migration_up(conn, migration_zero)
    |> result.map_error(types.PGOTransactionError),
  )
  use last <- result.map(get_last_applied_migration(conn))

  io.println(
    "Last applied migration: " <> int.to_string(last.0) <> "-" <> last.1,
  )
}

fn db_connect() -> Result(pog.Connection, types.MigrateError) {
  use url <- result.try(get_db_url())
  use config <- result.try(get_db_config(url))
  config |> pog.connect |> Ok
}

fn get_db_url() -> Result(String, types.MigrateError) {
  envoy.get("DATABASE_URL")
  |> result.replace_error(types.EnvVarError("DATABASE_URL"))
}

fn get_db_config(url: String) -> Result(pog.Config, types.MigrateError) {
  pog.url_config(url)
  |> result.replace_error(types.UrlError(url))
}

fn get_last_applied_migration(
  conn: pog.Connection,
) -> Result(#(Int, String), types.MigrateError) {
  pog.query(query_last_applied_migration)
  |> pog.returning(dynamic.tuple2(dynamic.int, dynamic.string))
  |> pog.execute(conn)
  |> result.map_error(types.PGOQueryError)
  |> result.then(fn(returned) {
    case returned {
      pog.Returned(0, _) | pog.Returned(_, []) -> Error(types.NoResultError)
      pog.Returned(_, [last, ..]) -> Ok(last)
    }
  })
}

fn find_migration(
  migrations: List(types.Migration),
  number: Int,
) -> Result(types.Migration, types.MigrateError) {
  list.find(migrations, fn(m) { m.number == number })
  |> result.replace_error(types.MigrationNotFoundError(number))
}
