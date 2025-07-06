import argv
import cigogne/internal/database
import cigogne/internal/fs
import cigogne/internal/migrations_utils
import cigogne/types
import gleam/bool
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import tempo/datetime
import tempo/instant

type SchemaData {
  SchemaData(generate: Bool, filename: String)
}

/// The MigrationEngine contains all the data required to apply and roll back migrations.
/// Checks are run in order to make sure the database is in a correct state.
/// When you have a MigrationEngine, you can be sure that your database is in a correct state to apply migrations.
pub opaque type MigrationEngine {
  MigrationEngine(
    db_data: database.DatabaseData,
    schema_data: SchemaData,
    applied: List(types.Migration),
    files: List(types.Migration),
  )
}

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

/// The default configuration you can use to get a MigrationEngine.
/// This configuration uses the DATABASE_URL envvar to connect to the database,
/// uses the 'default' schema, keeps migration data in the '_migrations' table
/// looks for migrations in 'priv/migrations/*.sql' files and generates a schema file in the sql.schema file
pub const default_config = types.Config(
  connection: types.EnvVarConfig,
  database_schema_to_use: "default",
  migration_table_name: "_migrations",
  schema_config: types.SchemaConfig(generate: True, filename: "./sql.schema"),
  migration_folder: "priv/migrations",
  migration_file_pattern: "*.sql",
)

/// Creates a MigrationEngine from a configuration.
/// This function will try to connect to the database, create the migrations table if it doesn't exist.
/// Then it will fetch the applied migrations and the existing migration files and check hashes do match.
pub fn create_migration_engine(
  config: types.Config,
) -> Result(MigrationEngine, types.MigrateError) {
  use db_data <- result.try(database.get_db_data(
    config.connection,
    config.database_schema_to_use,
    config.migration_table_name,
  ))

  use _ <- result.try(database.apply_cigogne_zero(db_data))
  use applied <- result.try(database.get_applied_migrations(db_data))
  use files <- result.try(fs.get_migrations(
    config.migration_folder,
    config.migration_file_pattern,
  ))
  use _ <- result.try(verify_applied_migration_hashes(applied, files))

  Ok(MigrationEngine(
    db_data:,
    schema_data: SchemaData(
      generate: config.schema_config.generate,
      filename: config.schema_config.filename,
    ),
    applied:,
    files:,
  ))
}

/// Create a new migration file in the specified folder with the provided name.
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
pub fn apply_next_migration(
  engine: MigrationEngine,
) -> Result(Nil, types.MigrateError) {
  use migration <- result.try(migrations_utils.find_first_non_applied_migration(
    engine.files,
    engine.applied,
  ))
  apply_migration(engine, migration)
}

/// Roll back the last applied migration.
pub fn roll_back_previous_migration(
  engine: MigrationEngine,
) -> Result(Nil, types.MigrateError) {
  use last <- result.try(get_last_applied_migration(engine))
  roll_back_migration(engine, last)
}

/// Apply or roll back the next `count` migrations.
pub fn execute_n_migrations(
  engine: MigrationEngine,
  count: Int,
) -> Result(Nil, types.MigrateError) {
  migrations_utils.find_n_migrations_to_apply(
    engine.files,
    engine.applied,
    count,
  )
  |> result.then(fn(migrations) {
    case count > 0 {
      True -> migrations |> list.try_each(apply_migration(engine, _))
      False -> migrations |> list.try_each(roll_back_migration(engine, _))
    }
  })
}

/// Apply migrations until we reach the last defined migration.
pub fn execute_migrations_to_last(
  engine: MigrationEngine,
) -> Result(Nil, types.MigrateError) {
  migrations_utils.find_all_non_applied_migration(engine.files, engine.applied)
  |> result.then(list.try_each(_, apply_migration(engine, _)))
}

/// Apply a migration to the database.
pub fn apply_migration(
  engine: MigrationEngine,
  migration: types.Migration,
) -> Result(Nil, types.MigrateError) {
  io.println(
    "\nApplying migration " <> migrations_utils.format_migration_name(migration),
  )

  database.apply_migration(engine.db_data, migration)
  |> result.map(fn(_) {
    io.println(
      "Migration applied : "
      <> migrations_utils.format_migration_name(migration),
    )
  })
}

/// Roll back a migration from the database.
pub fn roll_back_migration(
  engine: MigrationEngine,
  migration: types.Migration,
) -> Result(Nil, types.MigrateError) {
  io.println(
    "\nRolling back migration "
    <> migrations_utils.format_migration_name(migration),
  )

  database.rollback_migration(engine.db_data, migration)
  |> result.map(fn(_) {
    io.println(
      "Migration rolled back : "
      <> migrations_utils.format_migration_name(migration),
    )
  })
}

/// Get all defined migrations in your project.
pub fn get_migrations(
  engine: MigrationEngine,
) -> Result(List(types.Migration), types.MigrateError) {
  engine.files |> Ok
}

/// Get details about the schema of the database.
pub fn get_schema(engine: MigrationEngine) -> Result(String, types.MigrateError) {
  database.get_schema(engine.db_data)
}

/// Create or update a schema file if the engine configuration permits it.
pub fn update_schema(engine: MigrationEngine) {
  case engine.schema_data.generate {
    False -> Ok(Nil)
    True -> {
      use schema <- result.try(get_schema(engine))
      fs.write_schema_file(engine.schema_data.filename, schema)
      |> result.map(fn(_) { io.println("Schema file updated") })
    }
  }
}

fn get_last_applied_migration(
  engine: MigrationEngine,
) -> Result(types.Migration, types.MigrateError) {
  engine.applied
  |> list.last
  |> result.replace_error(types.NoMigrationToRollbackError)
  |> result.then(fn(mig) {
    use <- bool.guard(is_zero_migration(mig), Ok(mig))
    migrations_utils.find_migration(engine.files, mig)
  })
}

fn show(engine: MigrationEngine) -> Result(Nil, types.MigrateError) {
  use last <- result.try(get_last_applied_migration(engine))

  io.println(
    "Last applied migration: " <> migrations_utils.format_migration_name(last),
  )

  case engine.schema_data.generate {
    False -> Ok(Nil)
    True -> {
      use schema <- result.try(get_schema(engine))

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
fn verify_applied_migration_hashes(
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
          use file <- result.try(migrations_utils.find_migration(files, mig))
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
  migrations_utils.is_zero_migration(migration)
}

/// Apply a migration to the database if it hasn't been applied.
pub fn apply_migration_if_not_applied(
  engine: MigrationEngine,
  migration: types.Migration,
) -> Result(Nil, types.MigrateError) {
  use <- bool.guard(
    migrations_utils.find_migration(engine.applied, migration) |> result.is_ok,
    Ok(Nil),
  )
  apply_migration(engine, migration)
}
