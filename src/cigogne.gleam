import argv
import cigogne/config
import cigogne/internal/cli
import cigogne/internal/database
import cigogne/internal/fs
import cigogne/internal/migrations_utils
import cigogne/types
import gleam/bool
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleam/time/timestamp

/// The MigrationEngine contains all the data required to apply and roll back migrations.
/// Checks are run in order to make sure the database is in a correct state.
/// When you get a MigrationEngine, you can be sure that your database is in a correct state to apply migrations.
pub opaque type MigrationEngine {
  MigrationEngine(
    db_data: database.DatabaseData,
    applied: List(types.Migration),
    files: List(types.Migration),
    config: config.Config,
  )
}

pub fn main() {
  let args = argv.load().arguments
  let assert Ok(application_name) = config.get_app_name()
  let assert Ok(cigogne_config) = config.parse_config(application_name)
  use cli_action <- result.try(cli.get_action(application_name, args))

  case cli_action {
    cli.NewMigration(migrations:, name:) ->
      cigogne_config.migrations
      |> config.merge_migrations_config(migrations)
      |> new_migration(name)
    cli.ShowMigrations(config:) ->
      cigogne_config
      |> config.merge(config)
      |> create_engine()
      |> result.map(show)
    cli.MigrateUp(config:, count:) ->
      cigogne_config
      |> config.merge(config)
      |> create_engine()
      |> result.try(apply_n(_, count))
    cli.MigrateDown(config:, count:) ->
      cigogne_config
      |> config.merge(config)
      |> create_engine()
      |> result.try(rollback_n(_, count))
    cli.MigrateUpAll(config:) ->
      cigogne_config
      |> config.merge(config)
      |> create_engine()
      |> result.try(apply_all)
    cli.IncludeLib(config:, lib_name:) ->
      cigogne_config
      |> config.merge(config)
      |> create_engine()
      |> result.try(include_lib(_, lib_name))
    cli.RemoveLib(config:, lib_name:) ->
      cigogne_config
      |> config.merge(config)
      |> create_engine()
      |> result.try(remove_lib(_, lib_name))
    cli.UpdateConfig(config:) ->
      cigogne_config
      |> config.merge(config)
      |> update_config()
  }
  |> result.map_error(types.print_migrate_error)
}

/// Creates a MigrationEngine from a configuration.
/// This function will try to connect to the database, create the migrations table if it doesn't exist.
/// Then it will fetch the applied migrations and the existing migration files and check that hashes do match.
pub fn create_engine(
  config: config.Config,
) -> Result(MigrationEngine, types.MigrateError) {
  use db_data <- result.try(database.init(config))
  use _ <- result.try(database.apply_cigogne_zero(db_data))

  use applied <- result.try(database.get_applied_migrations(db_data))
  use files <- result.try(fs.get_migrations(config.migrations))
  use _ <- result.try(verify_applied_migration_hashes(applied, files))

  Ok(MigrationEngine(db_data:, applied:, files:, config:))
}

/// Create a new migration file in the specified folder with the provided name.
pub fn new_migration(
  config: config.MigrationsConfig,
  name: String,
) -> Result(Nil, types.MigrateError) {
  use path <- result.map(fs.create_new_migration_file(
    config,
    timestamp.system_time(),
    name,
  ))
  io.println("Migration file created : " <> path)
}

pub fn update_config(config: config.Config) -> Result(Nil, types.MigrateError) {
  config.write_config(config)
  |> result.replace_error(types.FileError("priv/cigogne.toml"))
}

/// Apply the next migration that wasn't applied yet.
pub fn apply(engine: MigrationEngine) -> Result(Nil, types.MigrateError) {
  use migration <- result.try(migrations_utils.find_first_non_applied_migration(
    engine.files,
    engine.applied,
  ))
  apply_migration(engine, migration)
}

/// Roll back the last applied migration.
pub fn rollback(engine: MigrationEngine) -> Result(Nil, types.MigrateError) {
  use last <- result.try(get_last_applied_migration(engine))
  rollback_migration(engine, last)
}

/// Apply the next `count` migrations.
pub fn apply_n(
  engine: MigrationEngine,
  count: Int,
) -> Result(Nil, types.MigrateError) {
  use <- bool.guard(count <= 0, Ok(Nil))

  migrations_utils.find_n_migrations_to_apply(
    engine.files,
    engine.applied,
    count,
  )
  |> result.try(fn(migrations) {
    migrations |> list.try_each(apply_migration(engine, _))
  })
}

/// Roll back `count` migrations.
pub fn rollback_n(
  engine: MigrationEngine,
  count: Int,
) -> Result(Nil, types.MigrateError) {
  use <- bool.guard(count <= 0, Ok(Nil))

  migrations_utils.find_n_migrations_to_rollback(
    engine.files,
    engine.applied,
    count,
  )
  |> result.try(fn(migrations) {
    migrations |> list.try_each(rollback_migration(engine, _))
  })
}

/// Apply migrations until we reach the last defined migration.
pub fn apply_all(engine: MigrationEngine) -> Result(Nil, types.MigrateError) {
  migrations_utils.find_all_non_applied_migration(engine.files, engine.applied)
  |> result.try(list.try_each(_, apply_migration(engine, _)))
}

pub fn include_lib(migration_engine: MigrationEngine, lib_name: String) {
  use lib_config <- result.try(
    config.parse_config(lib_name)
    |> result.replace_error(types.MissingDependencyError(lib_name)),
  )
  use lib_migrations <- result.try(fs.get_migrations(lib_config.migrations))
  let last_migration_for_dep =
    migration_engine.config.migrations.dependencies |> list.key_find(lib_name)

  let lib_migrations = case last_migration_for_dep {
    Error(_) -> lib_migrations
    Ok(name) ->
      lib_migrations
      |> list.drop_while(fn(mig) {
        mig |> migrations_utils.format_migration_name() != name
      })
      |> list.drop(1)
  }

  use _included_file <- result.try(fs.merge_migrations(
    migration_engine.config.migrations,
    lib_migrations,
    timestamp.system_time(),
    lib_name,
  ))
  let assert Ok(last_migration) = list.last(lib_migrations)

  let new_config =
    config.Config(
      ..migration_engine.config,
      migrations: config.MigrationsConfig(
        ..migration_engine.config.migrations,
        dependencies: {
          migration_engine.config.migrations.dependencies
          |> list.key_set(
            lib_name,
            last_migration |> migrations_utils.format_migration_name,
          )
        },
      ),
    )

  config.write_config(new_config)
  |> result.replace_error(types.FileError("priv/cigogne.toml"))
}

fn remove_lib(
  migration_engine: MigrationEngine,
  lib_name: String,
) -> Result(Nil, types.MigrateError) {
  let opposite_migrations =
    migration_engine.files
    |> list.filter(fn(mig) { mig.name == lib_name })
    |> list.map(fn(mig) {
      types.Migration(
        ..mig,
        queries_up: mig.queries_down,
        queries_down: mig.queries_up,
      )
    })
    |> list.reverse()

  use _included_file <- result.try(fs.merge_migrations(
    migration_engine.config.migrations,
    opposite_migrations,
    timestamp.system_time(),
    "remove_" <> lib_name,
  ))

  let new_config =
    config.Config(
      ..migration_engine.config,
      migrations: config.MigrationsConfig(
        ..migration_engine.config.migrations,
        dependencies: {
          migration_engine.config.migrations.dependencies
          |> list.filter(fn(dep) { dep.0 == lib_name })
        },
      ),
    )

  config.write_config(new_config)
  |> result.replace_error(types.FileError("priv/cigogne.toml"))
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
pub fn rollback_migration(
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

fn get_last_applied_migration(
  engine: MigrationEngine,
) -> Result(types.Migration, types.MigrateError) {
  engine.applied
  |> list.last
  |> result.replace_error(types.NoMigrationToRollbackError)
  |> result.try(fn(mig) {
    use <- bool.guard(is_zero_migration(mig), Ok(mig))
    migrations_utils.find_migration(engine.files, mig)
  })
}

fn show(engine: MigrationEngine) -> Nil {
  let migration_names =
    engine.applied |> list.map(migrations_utils.format_migration_name)

  io.println(
    "Applied migrations: [\n" <> migration_names |> string.join(",\n\t") <> "]",
  )
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

/// Checks if a migration is a zero migration (has been created with create_zero_migration)
pub fn is_zero_migration(migration: types.Migration) -> Bool {
  migrations_utils.is_zero_migration(migration)
}

/// Create a "zero" migration that should be applied before the user's migrations
pub fn create_zero_migration(
  name: String,
  queries_up: List(String),
  queries_down: List(String),
) -> types.Migration {
  migrations_utils.create_zero_migration(name, queries_up, queries_down)
}
