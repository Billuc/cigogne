import argv
import cigogne/internal/database
import cigogne/internal/fs
import cigogne/internal/migrations
import cigogne/internal/utils
import cigogne/types
import gleam/int
import gleam/io
import gleam/list
import gleam/order
import gleam/result
import pog
import tempo/naive_datetime

fn migration_zero() -> types.Migration {
  types.Migration(
    "",
    utils.tempo_epoch(),
    "CreateMigrationsTable",
    [
      "CREATE TABLE IF NOT EXISTS _migrations(
    id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(255) NOT NULL,
    sha256 VARCHAR(64) NOT NULL,
    createdAt TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    appliedAt TIMESTAMP NOT NULL DEFAULT NOW()
);",
    ],
    [],
    "",
  )
}

const query_insert_migration = "INSERT INTO _migrations(createdAt, name) VALUES ($1, $2);"

const query_drop_migration = "DELETE FROM _migrations WHERE name = $1 AND createdAt = $2;"

pub fn main() {
  case argv.load().arguments {
    ["show"] -> show()
    ["up"] -> migrate_up()
    ["down"] -> migrate_down()
    ["last"] -> migrate_to_last()
    ["apply", x] ->
      case int.parse(x) {
        Error(_) -> show_usage()
        Ok(mig) -> migrate_n(mig)
      }
    ["new", name] -> new_migration(name)
    _ -> show_usage()
  }
  |> result.map_error(types.print_migrate_error)
}

fn show_usage() -> Result(Nil, types.MigrateError) {
  io.println("=======================================")
  io.println("=               CIGOGNE               =")
  io.println("=======================================")
  io.println("")
  io.println("Usage: gleam run -m cigogne [command]")
  io.println("")
  io.println("List of commands:")
  io.println(" - show:  Show the last currently applied migration")
  io.println(" - up:    Migrate up one version / Apply one migration")
  io.println(" - down:  Migrate down one version / Rollback one migration")
  io.println(" - last:  Apply all migrations until the last one defined")
  io.println(
    " - apply N:  Apply or roll back N migrations (N can be positive or negative)",
  )
  io.println(
    " - new NAME: Create a new migration file in /priv/migrations with the specified name",
  )

  Ok(Nil)
}

/// Apply the next migration that wasn't applied yet.
/// This function will get the database url from the `DATABASE_URL` environment variable.
/// The migrations are then acquired from priv/migrations/*.sql files.
/// If successful, it will also create a file and write details of the new schema in it.
pub fn migrate_up() -> Result(Nil, types.MigrateError) {
  use url <- result.try(database.get_url())
  use conn <- result.try(database.connect(url))
  use _ <- result.try(apply_next_migration(conn))
  update_schema_file(url)
}

/// Verify the hash integrity of applied migrations.
/// If an already applied migration has been modified, it should most likely be run again by the user.
pub fn verify_applied_migration_hashes(
  conn: pog.Connection,
) -> Result(Nil, types.MigrateError) {
  use migs_db <- result.try(migrations.get_applied_migrations(conn))
  use migs_file <- result.try(get_migrations())

  list.try_each(migs_db, fn(mig) {
    use file <- result.try(migrations.find_migration(migs_file, mig))
    case mig.sha256 == file.sha256 {
      True -> Ok(Nil)
      False -> Error(types.FileHashChanged(mig.name))
    }
  })
}

/// Roll back the last applied migration.
/// This function will get the database url from the `DATABASE_URL` environment variable.
/// The migrations are then acquired from priv/migrations/*.sql files.
/// If successful, it will also create a file and write details of the new schema in it.
pub fn migrate_down() -> Result(Nil, types.MigrateError) {
  use url <- result.try(database.get_url())
  use conn <- result.try(database.connect(url))
  use _ <- result.try(roll_back_previous_migration(conn))
  update_schema_file(url)
}

/// Apply or roll back migrations until we reach the migration corresponding to the provided number.
/// This function will get the database url from the `DATABASE_URL` environment variable.
/// The migrations are then acquired from priv/migrations/*.sql files.
/// If successful, it will also create a file and write details of the new schema in it.
pub fn migrate_n(count: Int) -> Result(Nil, types.MigrateError) {
  use url <- result.try(database.get_url())
  use conn <- result.try(database.connect(url))
  use _ <- result.try(execute_n_migrations(conn, count))
  update_schema_file(url)
}

/// Apply migrations until we reach the last defined migration.
/// This function will get the database url from the `DATABASE_URL` environment variable.
/// The migrations are then acquired from priv/migrations/*.sql files.
/// If successful, it will also create a file and write details of the new schema in it.
pub fn migrate_to_last() -> Result(Nil, types.MigrateError) {
  use url <- result.try(database.get_url())
  use conn <- result.try(database.connect(url))
  use _ <- result.try(execute_migrations_to_last(conn))
  update_schema_file(url)
}

/// Create a new migration file in the `priv/migrations` folder with the provided name.
pub fn new_migration(name: String) -> Result(Nil, types.MigrateError) {
  use path <- result.map(fs.create_new_migration_file(
    naive_datetime.now_utc(),
    name,
  ))
  io.println("Migration file created : " <> path)
}

/// Apply the next migration that wasn't applied yet.
/// The migrations are acquired from priv/migrations/*.sql files.
/// This function does not create a schema file.
pub fn apply_next_migration(
  connection: pog.Connection,
) -> Result(Nil, types.MigrateError) {
  use _ <- result.try(apply_migration_zero_if_not_applied(connection))
  use _ <- result.try(verify_applied_migration_hashes(connection))
  use applied <- result.try(migrations.get_applied_migrations(connection))
  use migs <- result.try(fs.get_migrations())
  use migration <- result.try(migrations.find_first_non_applied_migration(
    migs,
    applied,
  ))
  apply_migration(connection, migration)
}

/// Roll back the last applied migration.
/// The migrations are acquired from **/migrations/*.sql files.
/// This function does not create a schema file.
pub fn roll_back_previous_migration(
  connection: pog.Connection,
) -> Result(Nil, types.MigrateError) {
  use _ <- result.try(apply_migration_zero_if_not_applied(connection))
  use _ <- result.try(verify_applied_migration_hashes(connection))
  use last <- result.try(get_last_applied_migration(connection))
  use migs <- result.try(fs.get_migrations())
  use migration <- result.try(migrations.find_migration(migs, last))
  roll_back_migration(connection, migration)
}

/// Apply or roll back migrations until we reach the migration corresponding to the provided number.
/// The migrations are acquired from **/migrations/*.sql files.
/// This function does not create a schema file.
pub fn execute_n_migrations(
  connection: pog.Connection,
  count: Int,
) -> Result(Nil, types.MigrateError) {
  use _ <- result.try(apply_migration_zero_if_not_applied(connection))
  use _ <- result.try(verify_applied_migration_hashes(connection))
  use applied <- result.try(migrations.get_applied_migrations(connection))
  use migs <- result.try(fs.get_migrations())

  migrations.find_n_migrations_to_apply(migs, applied, count)
  |> result.then(
    list.try_each(_, fn(migration) {
      case count > 0 {
        True -> apply_migration(connection, migration)
        False -> roll_back_migration(connection, migration)
      }
    }),
  )
}

/// Apply migrations until we reach the last defined migration.
/// The migrations are acquired from **/migrations/*.sql files.
/// This function does not create a schema file.
pub fn execute_migrations_to_last(
  connection: pog.Connection,
) -> Result(Nil, types.MigrateError) {
  use _ <- result.try(apply_migration_zero_if_not_applied(connection))
  use _ <- result.try(verify_applied_migration_hashes(connection))
  use applied <- result.try(migrations.get_applied_migrations(connection))
  use migs <- result.try(fs.get_migrations())

  migrations.find_all_non_applied_migration(migs, applied)
  |> result.then(
    list.try_each(_, fn(migration) { apply_migration(connection, migration) }),
  )
}

fn apply_migration_zero_if_not_applied(
  connection: pog.Connection,
) -> Result(Nil, types.MigrateError) {
  case migrations.get_applied_migrations(connection) {
    // 42P01: undefined_table --> _migrations table missing
    Error(types.PGOQueryError(pog.PostgresqlError(code, _, _)))
      if code == "42P01"
    -> apply_migration(connection, migration_zero())
    _ -> Ok(Nil)
  }
}

/// Apply a migration to the database.
/// This function does not create a schema file.
pub fn apply_migration(
  connection: pog.Connection,
  migration: types.Migration,
) -> Result(Nil, types.MigrateError) {
  io.println(
    "\nApplying migration "
    <> migration.timestamp |> naive_datetime.format("YYYYMMDDhhmmss")
    <> "-"
    <> migration.name,
  )

  let queries =
    list.map(migration.queries_up, pog.query)
    |> list.append([
      pog.query(query_insert_migration)
      |> pog.parameter(pog.timestamp(
        migration.timestamp |> utils.tempo_to_pog_timestamp,
      ))
      |> pog.parameter(pog.text(migration.name)),
    ])
  database.execute_batch(
    connection,
    queries,
    migrations.compare_migrations(migration, migration_zero()) == order.Eq,
  )
  |> result.map(fn(_) {
    io.println(
      "Migration applied : "
      <> migration.timestamp |> naive_datetime.format("YYYYMMDDhhmmss")
      <> "-"
      <> migration.name,
    )
  })
}

/// Roll back a migration from the database.
/// This function does not create a schema file.
pub fn roll_back_migration(
  connection: pog.Connection,
  migration: types.Migration,
) -> Result(Nil, types.MigrateError) {
  io.println(
    "\nRolling back migration "
    <> migration.timestamp |> naive_datetime.format("YYYYMMDDhhmmss")
    <> "-"
    <> migration.name,
  )

  let queries =
    list.map(migration.queries_down, pog.query)
    |> list.append([
      pog.query(query_drop_migration)
      |> pog.parameter(pog.text(migration.name))
      |> pog.parameter(pog.timestamp(
        migration.timestamp |> utils.tempo_to_pog_timestamp,
      )),
    ])
  database.execute_batch(
    connection,
    queries,
    migrations.compare_migrations(migration, migration_zero()) == order.Eq,
  )
  |> result.map(fn(_) {
    io.println(
      "Migration rolled back : "
      <> migration.timestamp |> naive_datetime.format("YYYYMMDDhhmmss")
      <> "-"
      <> migration.name,
    )
  })
}

/// Get all defined migrations in your project.
/// Migration files are searched in `/migrations` folders.
pub fn get_migrations() -> Result(List(types.Migration), types.MigrateError) {
  fs.get_migrations()
}

/// Get details about the schema of the database at the provided url.
pub fn get_schema(url: String) -> Result(String, types.MigrateError) {
  database.get_schema(url)
}

/// Create or update a schema file with details of the schema of the database at the provided url.
/// The schema file is created at `./sql.schema`.
pub fn update_schema_file(url: String) -> Result(Nil, types.MigrateError) {
  use schema <- result.try(get_schema(url))
  fs.write_schema_file(schema)
  |> result.map(fn(_) { io.println("Schema file updated") })
}

fn get_last_applied_migration(
  conn: pog.Connection,
) -> Result(types.Migration, types.MigrateError) {
  migrations.get_applied_migrations(conn)
  |> result.map(list.reverse)
  |> result.then(fn(migs) {
    case migs |> list.first {
      Error(Nil) -> Error(types.NoMigrationToRollbackError)
      Ok(mig) -> {
        case naive_datetime.compare(mig.timestamp, utils.tempo_epoch()) {
          order.Eq -> Error(types.NoMigrationToRollbackError)
          _ -> Ok(mig)
        }
      }
    }
  })
}

fn show() {
  use url <- result.try(database.get_url())
  use conn <- result.try(database.connect(url))
  use _ <- result.try(apply_migration(conn, migration_zero()))
  use _ <- result.try(verify_applied_migration_hashes(conn))
  use last <- result.try(get_last_applied_migration(conn))

  io.println(
    "Last applied migration: "
    <> last.timestamp |> naive_datetime.format("YYYYMMDDhhmmss")
    <> "-"
    <> last.name,
  )

  use schema <- result.try(get_schema(url))

  io.println("")
  io.println(schema)
  Ok(Nil)
}

/// Print a MigrateError to the standard error stream.
pub fn print_error(error: types.MigrateError) -> Nil {
  types.print_migrate_error(error)
}
