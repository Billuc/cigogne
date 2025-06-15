import argv
import cigogne/internal/database
import cigogne/internal/fs
import cigogne/internal/migrations
import cigogne/internal/utils
import cigogne/types
import gleam/bool
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/string
import pog
import tempo/datetime
import tempo/instant
import tempo/naive_datetime

pub const timestamp_format = fs.timestamp_format

fn cigogne_zero_migration() -> types.Migration {
  create_zero_migration(
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
  )
}

const query_insert_migration = "INSERT INTO _migrations(createdAt, name, sha256) VALUES ($1, $2, $3);"

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
    " - new NAME: Create a new migration file in priv/migrations with the specified name",
  )

  Ok(Nil)
}

/// The configuration used to create a MigrationEngine
pub type DatabaseConfig {
  /// The default configuration. It uses the DATABASE_URL envvar to connect
  EnvVarConfig
  /// A configuration using the URL to the database
  UrlConfig(url: String)
  /// A configuration using a pog.Config to connect. It disables schema generation.
  PogConfig(config: pog.Config)
  /// A configuration using a pog.Connection directly. It disables schema generation.
  ConnectionConfig(connection: pog.Connection)
}

/// The MigrationEngine contains all the data required to apply and roll back migrations.
pub type MigrationEngine {
  MigrationEngine(
    db_url: option.Option(String),
    connection: pog.Connection,
    applied: List(types.Migration),
    files: List(types.Migration),
    zero_applied: Bool,
  )
}

/// Creates a MigrationEngine from a configuration.
/// This function will try to connect to the database.
/// Then it will fetch the applied migrations and the existing migration files.
pub fn create_migration_engine(
  config: DatabaseConfig,
) -> Result(MigrationEngine, types.MigrateError) {
  case config {
    ConnectionConfig(conn) -> create_engine_from_conn(conn)
    EnvVarConfig -> {
      use url <- result.try(database.get_url())
      create_engine_from_url(url)
    }
    PogConfig(conf) -> create_engine_from_conn(conf |> pog.connect)
    UrlConfig(url) -> create_engine_from_url(url)
  }
}

fn create_engine_from_conn(
  connection: pog.Connection,
) -> Result(MigrationEngine, types.MigrateError) {
  use #(applied, zero_applied) <- result.try(get_applied_if_migration_zero(
    connection,
  ))
  use files <- result.try(fs.get_migrations())

  Ok(MigrationEngine(
    db_url: option.None,
    connection:,
    applied:,
    files:,
    zero_applied:,
  ))
}

fn create_engine_from_url(
  url: String,
) -> Result(MigrationEngine, types.MigrateError) {
  use connection <- result.try(database.connect(url))
  use #(applied, zero_applied) <- result.try(get_applied_if_migration_zero(
    connection,
  ))
  use files <- result.try(fs.get_migrations())

  Ok(MigrationEngine(
    db_url: option.Some(url),
    connection:,
    applied:,
    files:,
    zero_applied:,
  ))
}

fn get_applied_if_migration_zero(
  connection: pog.Connection,
) -> Result(#(List(types.Migration), Bool), types.MigrateError) {
  case migrations.get_applied_migrations(connection) {
    // 42P01: undefined_table --> _migrations table missing
    Error(types.PGOQueryError(pog.PostgresqlError(code, _, _)))
      if code == "42P01"
    -> Ok(#([], False))
    Error(err) -> Error(err)
    Ok(migs) -> Ok(#(migs, True))
  }
}

/// Apply the next migration that wasn't applied yet.
/// This function will get the database url from the `DATABASE_URL` environment variable.
/// The migrations are then acquired from priv/migrations/*.sql files.
/// If successful, it will also create a file and write details of the new schema in it.
pub fn migrate_up() -> Result(Nil, types.MigrateError) {
  use engine <- result.try(create_migration_engine(EnvVarConfig))
  use _ <- result.try(apply_next_migration(engine))
  update_schema(engine)
}

/// Roll back the last applied migration.
/// This function will get the database url from the `DATABASE_URL` environment variable.
/// The migrations are then acquired from priv/migrations/*.sql files.
/// If successful, it will also create a file and write details of the new schema in it.
pub fn migrate_down() -> Result(Nil, types.MigrateError) {
  use engine <- result.try(create_migration_engine(EnvVarConfig))
  use _ <- result.try(roll_back_previous_migration(engine))
  update_schema(engine)
}

/// Apply or roll back migrations until we reach the migration corresponding to the provided number.
/// This function will get the database url from the `DATABASE_URL` environment variable.
/// The migrations are then acquired from priv/migrations/*.sql files.
/// If successful, it will also create a file and write details of the new schema in it.
pub fn migrate_n(count: Int) -> Result(Nil, types.MigrateError) {
  use engine <- result.try(create_migration_engine(EnvVarConfig))
  use _ <- result.try(execute_n_migrations(engine, count))
  update_schema(engine)
}

/// Apply migrations until we reach the last defined migration.
/// This function will get the database url from the `DATABASE_URL` environment variable.
/// The migrations are then acquired from priv/migrations/*.sql files.
/// If successful, it will also create a file and write details of the new schema in it.
pub fn migrate_to_last() -> Result(Nil, types.MigrateError) {
  use engine <- result.try(create_migration_engine(EnvVarConfig))
  use _ <- result.try(execute_migrations_to_last(engine))
  update_schema(engine)
}

/// Create a new migration file in the `priv/migrations` folder with the provided name.
pub fn new_migration(name: String) -> Result(Nil, types.MigrateError) {
  use path <- result.map(fs.create_new_migration_file(
    instant.now()
      |> instant.as_utc_datetime()
      |> datetime.drop_offset(),
    name,
  ))
  io.println("Migration file created : " <> path)
}

/// Apply the next migration that wasn't applied yet.
/// The migrations are acquired from priv/migrations/*.sql files.
/// This function does not create a schema file.
pub fn apply_next_migration(
  engine: MigrationEngine,
) -> Result(Nil, types.MigrateError) {
  use _ <- result.try(apply_migration_zero_if_not_applied(engine))
  use _ <- result.try(verify_applied_migration_hashes(engine))
  use migration <- result.try(migrations.find_first_non_applied_migration(
    engine.files,
    engine.applied,
  ))
  apply_migration(engine, migration)
}

/// Roll back the last applied migration.
/// The migrations are acquired from priv/migrations/*.sql files.
/// This function does not create a schema file.
pub fn roll_back_previous_migration(
  engine: MigrationEngine,
) -> Result(Nil, types.MigrateError) {
  use _ <- result.try(apply_migration_zero_if_not_applied(engine))
  use _ <- result.try(verify_applied_migration_hashes(engine))
  use last <- result.try(get_last_applied_migration(engine))
  roll_back_migration(engine, last)
}

/// Apply or roll back migrations until we reach the migration corresponding to the provided number.
/// The migrations are acquired from priv/migrations/*.sql files.
/// This function does not create a schema file.
pub fn execute_n_migrations(
  engine: MigrationEngine,
  count: Int,
) -> Result(Nil, types.MigrateError) {
  use _ <- result.try(apply_migration_zero_if_not_applied(engine))
  use _ <- result.try(verify_applied_migration_hashes(engine))

  migrations.find_n_migrations_to_apply(engine.files, engine.applied, count)
  |> result.then(
    list.try_each(_, fn(migration) {
      case count > 0 {
        True -> apply_migration(engine, migration)
        False -> roll_back_migration(engine, migration)
      }
    }),
  )
}

/// Apply migrations until we reach the last defined migration.
/// The migrations are acquired from priv/migrations/*.sql files.
/// This function does not create a schema file.
pub fn execute_migrations_to_last(
  engine: MigrationEngine,
) -> Result(Nil, types.MigrateError) {
  use _ <- result.try(apply_migration_zero_if_not_applied(engine))
  use _ <- result.try(verify_applied_migration_hashes(engine))

  migrations.find_all_non_applied_migration(engine.files, engine.applied)
  |> result.then(list.try_each(_, apply_migration(engine, _)))
}

fn apply_migration_zero_if_not_applied(
  engine: MigrationEngine,
) -> Result(Nil, types.MigrateError) {
  use <- bool.guard(engine.zero_applied, Ok(Nil))
  apply_migration(engine, cigogne_zero_migration())
}

/// Apply a migration to the database.
/// This function does not create a schema file.
pub fn apply_migration(
  engine: MigrationEngine,
  migration: types.Migration,
) -> Result(Nil, types.MigrateError) {
  io.println("\nApplying migration " <> fs.format_migration_name(migration))

  let queries =
    list.map(migration.queries_up, pog.query)
    |> list.append([
      pog.query(query_insert_migration)
      |> pog.parameter(pog.timestamp(
        migration.timestamp |> utils.tempo_to_pog_timestamp,
      ))
      |> pog.parameter(pog.text(migration.name))
      |> pog.parameter(pog.text(migration.sha256)),
    ])
  database.execute_batch(
    engine.connection,
    queries,
    migrations.compare_migrations(migration, cigogne_zero_migration())
      == order.Eq,
  )
  |> result.map(fn(_) {
    io.println("Migration applied : " <> fs.format_migration_name(migration))
  })
}

/// Roll back a migration from the database.
/// This function does not create a schema file.
pub fn roll_back_migration(
  engine: MigrationEngine,
  migration: types.Migration,
) -> Result(Nil, types.MigrateError) {
  io.println("\nRolling back migration " <> fs.format_migration_name(migration))

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
    engine.connection,
    queries,
    migrations.compare_migrations(migration, cigogne_zero_migration())
      == order.Eq,
  )
  |> result.map(fn(_) {
    io.println(
      "Migration rolled back : " <> fs.format_migration_name(migration),
    )
  })
}

/// Get all defined migrations in your project.
/// Migration files are searched in the `priv/migrations` folder.
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

/// Create or update a schema file if the engine configuration permits it.
/// See update_schema_file.
pub fn update_schema(engine: MigrationEngine) {
  case engine.db_url {
    option.None -> {
      io.println("No URL provided, schema will not be updated")
      Ok(Nil)
    }
    option.Some(url) -> update_schema_file(url)
  }
}

fn get_last_applied_migration(
  engine: MigrationEngine,
) -> Result(types.Migration, types.MigrateError) {
  case engine.applied |> list.last {
    Error(Nil) -> Error(types.NoMigrationToRollbackError)
    Ok(mig) -> {
      // Zero migrations can't be rolled back
      use <- bool.guard(
        is_zero_migration(mig),
        Error(types.NoMigrationToRollbackError),
      )
      migrations.find_migration(engine.files, mig)
    }
  }
}

fn show() {
  use engine <- result.try(create_migration_engine(EnvVarConfig))
  use _ <- result.try(apply_migration_zero_if_not_applied(engine))
  use _ <- result.try(verify_applied_migration_hashes(engine))
  use last <- result.try(get_last_applied_migration(engine))

  io.println(
    "Last applied migration: "
    <> last.timestamp |> naive_datetime.format(timestamp_format)
    <> "-"
    <> last.name,
  )

  case engine.db_url {
    option.None -> {
      io.println("Couldn't get schema because no URL was provided")
      Ok(Nil)
    }
    option.Some(url) -> {
      use schema <- result.try(get_schema(url))

      io.println("")
      io.println(schema)
      Ok(Nil)
    }
  }
}

/// Print a MigrateError to the standard error stream.
pub fn print_error(error: types.MigrateError) -> Nil {
  types.print_migrate_error(error)
}

/// Verify the hash integrity of applied migrations.
/// If an already applied migration has been modified, it should most likely be run again by the user.
pub fn verify_applied_migration_hashes(
  engine: MigrationEngine,
) -> Result(Nil, types.MigrateError) {
  list.try_each(engine.applied, fn(mig) {
    // Not checking zero migrations because we don't have their queries here
    use <- bool.guard(is_zero_migration(mig), Ok(Nil))

    use file <- result.try(migrations.find_migration(engine.files, mig))
    case mig.sha256 == file.sha256 {
      True -> Ok(Nil)
      False -> Error(types.FileHashChanged(mig.timestamp, mig.name))
    }
  })
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

/// Checks if a migration is a zero migration (has been created with create_zero_migration)
pub fn is_zero_migration(migration: types.Migration) -> Bool {
  migrations.is_zero_migration(migration)
}

/// Apply a migration to the database if it hasn't been applied.
/// This function does not create a schema file.
pub fn apply_migration_if_not_applied(
  engine: MigrationEngine,
  migration: types.Migration,
) -> Result(Nil, types.MigrateError) {
  use <- bool.guard(
    migrations.find_migration(engine.applied, migration) |> result.is_ok,
    Ok(Nil),
  )
  apply_migration(engine, migration)
}
