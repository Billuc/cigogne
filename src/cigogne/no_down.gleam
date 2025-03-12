import argv
import cigogne/internal/no_down/database
import cigogne/internal/no_down/fs
import cigogne/internal/no_down/migrations
import cigogne/no_down/types
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/list
import gleam/order
import gleam/result
import pog

fn migration_zero() -> types.Migration {
  types.Migration("", 0, "CreateMigrationsTable", [
    "CREATE TABLE IF NOT EXISTS _migrations(
    id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(255) NOT NULL,
    index INTEGER NOT NULL,
    appliedAt TIMESTAMP NOT NULL DEFAULT NOW()
);",
  ])
}

const query_applied_migrations = "SELECT index, name FROM _migrations ORDER BY appliedAt ASC;"

const query_insert_migration = "INSERT INTO _migrations(index, name) VALUES ($1, $2);"

pub fn main() {
  case argv.load().arguments {
    ["show"] -> show()
    ["up"] -> migrate_up()
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
  io.println("=          CIGOGNE (No Down)          =")
  io.println("=======================================")
  io.println("")
  io.println("Usage: gleam run -m cigogne/no_down [command]")
  io.println("")
  io.println("List of commands:")
  io.println(" - show:  Show the last currently applied migration")
  io.println(" - up:    Migrate up one version / Apply one migration")
  io.println(" - last:  Apply all migrations until the last one defined")
  io.println(" - apply N:  Apply N migrations (N can only be positive)")
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

/// Apply n migrations.  
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
  fs.create_migration_folder()
  |> result.then(fn(_) { fs.get_migrations() })
  |> result.map(fn(migrations) {
    list.fold(migrations, 0, fn(acc, curr) { int.max(acc, curr.index) })
  })
  |> result.then(fn(last_index) {
    fs.create_new_migration_file(last_index + 1, name)
  })
  |> result.map(fn(path) { io.println("Migration file created : " <> path) })
}

/// Apply the next migration that wasn't applied yet.  
/// The migrations are acquired from priv/migrations/*.sql files.  
/// This function does not create a schema file.
pub fn apply_next_migration(
  connection: pog.Connection,
) -> Result(Nil, types.MigrateError) {
  use _ <- result.try(apply_migration_zero_if_not_applied(connection))
  use applied <- result.try(get_applied_migrations(connection))
  use migs <- result.try(fs.get_migrations())
  use migration <- result.try(migrations.find_first_non_applied_migration(
    migs,
    applied,
  ))
  apply_migration(connection, migration)
}

/// Apply or roll back migrations until we reach the migration corresponding to the provided number.  
/// The migrations are acquired from **/migrations/*.sql files.  
/// This function does not create a schema file.
pub fn execute_n_migrations(
  connection: pog.Connection,
  count: Int,
) -> Result(Nil, types.MigrateError) {
  use _ <- result.try(apply_migration_zero_if_not_applied(connection))
  use applied <- result.try(get_applied_migrations(connection))
  use migs <- result.try(fs.get_migrations())

  migrations.find_n_migrations_to_apply(migs, applied, count)
  |> result.then(
    list.try_each(_, fn(migration) { apply_migration(connection, migration) }),
  )
}

/// Apply migrations until we reach the last defined migration.  
/// The migrations are acquired from **/migrations/*.sql files.  
/// This function does not create a schema file.
pub fn execute_migrations_to_last(
  connection: pog.Connection,
) -> Result(Nil, types.MigrateError) {
  use _ <- result.try(apply_migration_zero_if_not_applied(connection))
  use applied <- result.try(get_applied_migrations(connection))
  use migs <- result.try(fs.get_migrations())

  migrations.find_all_non_applied_migration(migs, applied)
  |> result.then(
    list.try_each(_, fn(migration) { apply_migration(connection, migration) }),
  )
}

fn apply_migration_zero_if_not_applied(
  connection: pog.Connection,
) -> Result(Nil, types.MigrateError) {
  case get_applied_migrations(connection) {
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
    <> migration.index |> int.to_string
    <> "-"
    <> migration.name,
  )

  let queries =
    list.map(migration.queries, pog.query)
    |> list.append([
      pog.query(query_insert_migration)
      |> pog.parameter(pog.int(migration.index))
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
      <> migration.index |> int.to_string
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
  get_applied_migrations(conn)
  |> result.map(list.reverse)
  |> result.then(fn(migs) {
    migs |> list.first |> result.replace_error(types.NoAppliedMigrationError)
  })
}

fn get_applied_migrations(
  conn: pog.Connection,
) -> Result(List(types.Migration), types.MigrateError) {
  pog.query(query_applied_migrations)
  |> pog.returning({
    use index <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    decode.success(#(index, name))
  })
  |> pog.execute(conn)
  |> result.map_error(types.PGOQueryError)
  |> result.then(fn(returned) {
    case returned {
      pog.Returned(0, _) | pog.Returned(_, []) -> Error(types.NoResultError)
      pog.Returned(_, applied) ->
        applied
        |> list.map(fn(data) { types.Migration("", data.0, data.1, []) })
        |> Ok
    }
  })
}

fn show() {
  use url <- result.try(database.get_url())
  use conn <- result.try(database.connect(url))
  use _ <- result.try(apply_migration(conn, migration_zero()))
  use last <- result.try(get_last_applied_migration(conn))

  io.println(
    "Last applied migration: "
    <> last.index |> int.to_string
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
