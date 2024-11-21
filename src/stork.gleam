import argv
import envoy
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import pog
import stork/commands
import stork/internal/database
import stork/internal/fs
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

const query_insert_migration = "INSERT INTO _migrations VALUES ($1, $2);"

const query_drop_migration = "DELETE FROM _migrations WHERE id = $1;"

pub fn main() {
  case argv.load().arguments {
    // ["show"] -> show_last_migration()
    ["up"] -> migrate_up()
    ["down"] -> migrate_down()
    [x] ->
      case int.parse(x) {
        Error(_) -> show_usage()
        Ok(mig) -> migrate_to(mig)
      }
    _ -> show_usage()
  }
  |> result.map_error(types.print_migrate_error)
}

fn show_usage() -> Result(Nil, types.MigrateError) {
  io.println("=======================================")
  io.println("=            GLITR MIGRATE            =")
  io.println("=======================================")
  io.println("")
  io.println("Usage: gleam run -m glitr/migrate [command|num]")
  io.println("")
  io.println("List of commands:")
  io.println(" - show:  Show the last currently applied migration")
  io.println(" - up:    Migrate up one version / Apply one migration")
  io.println(" - down:  Migrate down one version / Rollback one migration")
  io.println("")
  io.println(
    "Alternatively, a migration number can be passed and all migration between the currently",
  )
  io.println(
    "applied migration and the migration with the provided number will be applied/rolled back",
  )

  Ok(Nil)
}

pub fn migrate_up() {
  use url <- result.try(database.get_url())
  use conn <- result.try(database.connect(url))
  use _ <- result.try(apply_migration(conn, migration_zero))
  use last <- result.try(get_last_applied_migration(conn))
  use migrations <- result.try(fs.get_migrations())
  use migration <- result.try(fs.find_migration(migrations, last.0 + 1))
  use _ <- result.try(apply_migration(conn, migration))
  use schema <- result.try(database.get_schema(url))
  fs.write_schema_file(schema)
}

pub fn migrate_down() {
  use url <- result.try(database.get_url())
  use conn <- result.try(database.connect(url))
  use _ <- result.try(apply_migration(conn, migration_zero))
  use last <- result.try(get_last_applied_migration(conn))
  use migrations <- result.try(fs.get_migrations())
  use migration <- result.try(fs.find_migration(migrations, last.0))
  use _ <- result.try(roll_back_migration(conn, migration))
  use schema <- result.try(database.get_schema(url))
  fs.write_schema_file(schema)
}

pub fn migrate_to(migration_number: Int) {
  use url <- result.try(database.get_url())
  use conn <- result.try(database.connect(url))
  use _ <- result.try(apply_migration(conn, migration_zero))
  use last <- result.try(get_last_applied_migration(conn))
  use migrations <- result.try(fs.get_migrations())
  use _ <- result.try(
    list.range(last.0, migration_number)
    |> list.try_map(fs.find_migration(migrations, _))
    |> result.then(list.try_each(_, fn(migration) {
      case migration_number > last.0 {
        True -> apply_migration(conn, migration)
        False -> roll_back_migration(conn, migration)
      }
    })),
  )
  use schema <- result.try(database.get_schema(url))
  fs.write_schema_file(schema)
}

pub fn apply_migration(connection: pog.Connection, migration: types.Migration) {
  io.println(
    "\nApplying migration "
    <> int.to_string(migration.number)
    <> "-"
    <> migration.name
    <> "\n",
  )

  let queries =
    list.map(migration.queries_up, pog.query)
    |> list.append([
      pog.query(query_insert_migration)
      |> pog.parameter(pog.int(migration.number))
      |> pog.parameter(pog.text(migration.name)),
    ])
  database.execute_batch(connection, migration.number, queries)
}

pub fn roll_back_migration(
  connection: pog.Connection,
  migration: types.Migration,
) {
  io.println(
    "\nRolling back migration "
    <> int.to_string(migration.number)
    <> "-"
    <> migration.name
    <> "\n",
  )

  let queries =
    list.map(migration.queries_down, pog.query)
    |> list.append([
      pog.query(query_drop_migration)
      |> pog.parameter(pog.int(migration.number)),
    ])
  database.execute_batch(connection, migration.number, queries)
}

pub fn get_migrations() {
  todo
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
