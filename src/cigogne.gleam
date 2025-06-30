import argv
import cigogne/internal/database
import cigogne/internal/db_operations
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

pub fn main() {
  {
    let config = default_config

    case argv.load().arguments {
      ["new", name] -> new_migration(config.migration_folder, name)
      _ as args -> {
        use engine <- result.try(create_migration_engine(config))

        case args {
          ["show"] -> show(engine)
          ["up"] ->
            apply_next_migration(engine)
            |> result.then(fn(_) { update_schema(engine) })
          ["down"] ->
            roll_back_previous_migration(engine)
            |> result.then(fn(_) { update_schema(engine) })

          ["last"] ->
            execute_migrations_to_last(engine)
            |> result.then(fn(_) { update_schema(engine) })

          ["apply", x] ->
            case int.parse(x) {
              Error(_) -> show_usage()
              Ok(mig) ->
                execute_n_migrations(engine, mig)
                |> result.then(fn(_) { update_schema(engine) })
            }
          _ -> show_usage()
        }
      }
    }
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

pub const default_config = types.Config(
  connection: types.EnvVarConfig,
  database_schema_to_use: "default",
  migration_table_name: "_migrations",
  schema_config: types.SchemaConfig(generate: True, filename: "./sql.schema"),
  migration_folder: "priv/migrations",
  migration_file_pattern: "*.sql",
)

fn create_pog_connection(
  config: types.ConnectionConfig,
) -> Result(#(pog.Connection, option.Option(String)), types.MigrateError) {
  case config {
    types.ConnectionConfig(connection:) -> Ok(#(connection, option.None))
    types.EnvVarConfig -> {
      use url <- result.try(database.get_url())
      use connection <- result.try(database.connect(url))
      #(connection, option.Some(url)) |> Ok
    }
    types.PogConfig(config:) -> Ok(#(config |> pog.connect, option.None))
    types.UrlConfig(url:) -> {
      use connection <- result.try(database.connect(url))
      Ok(#(connection, option.Some(url)))
    }
  }
}

/// CreatesConnectionConfiggine from a configuration.
/// This function will try to connect to the database.
/// Then it will fetch the applied migrations and the existing migration files.
pub fn create_migration_engine(
  config: types.Config,
) -> Result(types.MigrationEngine, types.MigrateError) {
  use #(connection, db_url) <- result.try(create_pog_connection(
    config.connection,
  ))
  let db_data =
    types.DatabaseData(
      connection,
      config.migration_table_name,
      config.database_schema_to_use,
    )

  use _ <- result.try(db_operations.apply_cigogne_zero(db_data))
  use applied <- result.try(db_operations.get_applied_migrations(db_data))
  use files <- result.try(fs.get_migrations(
    config.migration_folder,
    config.migration_file_pattern,
  ))
  use _ <- result.try(verify_applied_migration_hashes(applied, files))

  Ok(types.MigrationEngine(
    db_data:,
    schema_data: types.SchemaData(
      db_url: bool.guard(config.schema_config.generate, db_url, fn() {
        option.None
      }),
      filename: config.schema_config.filename,
    ),
    applied:,
    files:,
  ))
}

/// Create a new migration file in the `priv/migrations` folder with the provided name.
pub fn new_migration(
  migrations_folder: String,
  name: String,
) -> Result(Nil, types.MigrateError) {
  use path <- result.map(fs.create_new_migration_file(
    migrations_folder,
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
  engine: types.MigrationEngine,
) -> Result(Nil, types.MigrateError) {
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
  engine: types.MigrationEngine,
) -> Result(Nil, types.MigrateError) {
  use last <- result.try(get_last_applied_migration(engine))
  roll_back_migration(engine, last)
}

/// Apply or roll back migrations until we reach the migration corresponding to the provided number.
/// The migrations are acquired from priv/migrations/*.sql files.
/// This function does not create a schema file.
pub fn execute_n_migrations(
  engine: types.MigrationEngine,
  count: Int,
) -> Result(Nil, types.MigrateError) {
  migrations.find_n_migrations_to_apply(engine.files, engine.applied, count)
  |> result.then(fn(migrations) {
    case count > 0 {
      True -> migrations |> list.try_each(apply_migration(engine, _))
      False -> migrations |> list.try_each(roll_back_migration(engine, _))
    }
  })
}

/// Apply migrations until we reach the last defined migration.
/// The migrations are acquired from priv/migrations/*.sql files.
/// This function does not create a schema file.
pub fn execute_migrations_to_last(
  engine: types.MigrationEngine,
) -> Result(Nil, types.MigrateError) {
  migrations.find_all_non_applied_migration(engine.files, engine.applied)
  |> result.then(list.try_each(_, apply_migration(engine, _)))
}

/// Apply a migration to the database.
/// This function does not create a schema file.
pub fn apply_migration(
  engine: types.MigrationEngine,
  migration: types.Migration,
) -> Result(Nil, types.MigrateError) {
  io.println("\nApplying migration " <> fs.format_migration_name(migration))

  db_operations.apply_migration(engine.db_data, migration)
  |> result.map(fn(_) {
    io.println("Migration applied : " <> fs.format_migration_name(migration))
  })
}

/// Roll back a migration from the database.
/// This function does not create a schema file.
pub fn roll_back_migration(
  engine: types.MigrationEngine,
  migration: types.Migration,
) -> Result(Nil, types.MigrateError) {
  io.println("\nRolling back migration " <> fs.format_migration_name(migration))

  db_operations.rollback_migration(engine.db_data, migration)
  |> result.map(fn(_) {
    io.println(
      "Migration rolled back : " <> fs.format_migration_name(migration),
    )
  })
}

/// Get all defined migrations in your project.
/// Migration files are searched in the `priv/migrations` folder.
pub fn get_migrations(
  engine: types.MigrationEngine,
) -> Result(List(types.Migration), types.MigrateError) {
  engine.files |> Ok
}

/// Get details about the schema of the database at the provided url.
pub fn get_schema(url: String) -> Result(String, types.MigrateError) {
  database.get_schema(url)
}

/// Create or update a schema file if the engine configuration permits it.
/// See update_schema_file.
pub fn update_schema(engine: types.MigrationEngine) {
  case engine.schema_data.db_url {
    option.None -> {
      io.println("No URL provided, schema will not be updated")
      Ok(Nil)
    }
    option.Some(url) -> {
      use schema <- result.try(get_schema(url))
      fs.write_schema_file(engine.schema_data.filename, schema)
      |> result.map(fn(_) { io.println("Schema file updated") })
    }
  }
}

fn get_last_applied_migration(
  engine: types.MigrationEngine,
) -> Result(types.Migration, types.MigrateError) {
  engine.applied
  |> list.last
  |> result.replace_error(types.NoMigrationToRollbackError)
  |> result.then(fn(mig) {
    use <- bool.guard(is_zero_migration(mig), Ok(mig))
    migrations.find_migration(engine.files, mig)
  })
}

fn show(engine: types.MigrationEngine) -> Result(Nil, types.MigrateError) {
  use last <- result.try(get_last_applied_migration(engine))

  io.println(
    "Last applied migration: "
    <> last.timestamp |> naive_datetime.format(timestamp_format)
    <> "-"
    <> last.name,
  )

  case engine.schema_data.db_url {
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
  applied: List(types.Migration),
  files: List(types.Migration),
) -> Result(Nil, types.MigrateError) {
  case applied {
    [] -> Ok(Nil)
    [mig, ..rest] -> {
      case is_zero_migration(mig) {
        // Not checking zero migrations because we don't have their queries here
        True -> verify_applied_migration_hashes(rest, files)
        False -> {
          use file <- result.try(migrations.find_migration(files, mig))
          case mig.sha256 == file.sha256 {
            False -> Error(types.FileHashChanged(mig.timestamp, mig.name))
            True -> verify_applied_migration_hashes(rest, files)
          }
        }
      }
    }
  }
}

/// Checks if a migration is a zero migration (has been created with create_zero_migration)
pub fn is_zero_migration(migration: types.Migration) -> Bool {
  migrations.is_zero_migration(migration)
}

/// Apply a migration to the database if it hasn't been applied.
/// This function does not create a schema file.
pub fn apply_migration_if_not_applied(
  engine: types.MigrationEngine,
  migration: types.Migration,
) -> Result(Nil, types.MigrateError) {
  use <- bool.guard(
    migrations.find_migration(engine.applied, migration) |> result.is_ok,
    Ok(Nil),
  )
  apply_migration(engine, migration)
}
