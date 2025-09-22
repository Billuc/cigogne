import argv
import cigogne/config
import cigogne/internal/cli
import cigogne/internal/database
import cigogne/internal/fs
import cigogne/internal/parser_formatter
import cigogne/internal/utils
import cigogne/migration
import gleam/bool
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/time/timestamp

/// The MigrationEngine contains all the data required to apply and roll back migrations.
/// When you get a MigrationEngine, you can be sure that your database is in a correct state to apply migrations.
/// You can get a MigrationEngine by using the `create_engine` function.
///
/// Example:
/// ```gleam
/// use config <- result.try(config.get("my_app"))
/// use engine <- result.try(cigogne.create_engine(config))
///
/// // Use the engine to apply or rollback migrations
/// ```
pub opaque type MigrationEngine {
  MigrationEngine(
    db_data: database.DatabaseData,
    files: List(migration.Migration),
    applied: List(migration.Migration),
    non_applied: List(migration.Migration),
    config: config.Config,
  )
}

/// The CigogneError type contains all the possible errors that can happen in Cigogne.
/// Some errors are just wrappers around other error types from the different modules.
pub type CigogneError {
  DatabaseError(error: database.DatabaseError)
  FSError(error: fs.FSError)
  MigrationError(error: migration.MigrationError)
  ParserError(error: parser_formatter.ParserError)
  ConfigError(error: config.ConfigError)
  NothingToRollback
  NothingToApply
  LibNotIncluded(name: String)
  CompoundError(errors: List(CigogneError))
}

/// The main entry point of the Cigogne CLI.
/// 
/// Example usage:
/// ```sh
/// # List all possible actions
/// gleam run -m cigogne help
/// # Create a new migration
/// gleam run -m cigogne new --name AddUsers
/// # Apply a single migration
/// gleam run -m cigogne up
/// # Apply the next 3 migrations
/// gleam run -m cigogne up --count 3
/// # Apply all pending migrations
/// gleam run -m cigogne up-all
/// # Rollback a single migration
/// gleam run -m cigogne down
/// ```
pub fn main() {
  let args = argv.load().arguments
  let assert Ok(application_name) = config.get_app_name()
  let assert Ok(cigogne_config) = config.get(application_name)
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
    cli.InitConfig -> cigogne_config |> update_config()
    cli.PrintUnapplied(config:) ->
      cigogne_config
      |> config.merge(config)
      |> create_engine()
      |> result.map(print_unapplied)
  }
  |> result.map_error(print_error)
}

/// Creates a MigrationEngine from a configuration.
/// This function will try to connect to the database, create the migrations table if it doesn't exist.
/// Then it will fetch the applied migrations and the existing migration files and check that hashes do match.
/// 
/// Example usage:
/// ```gleam
/// import cigogne/config
/// import cigogne/cigogne
/// 
/// pub fn main() {
///   use app_name <- result.try(config.get_app_name())
///   use config <- result.try(config.get(app_name))
///   use engine <- result.try(cigogne.create_engine(config))
/// 
///   // Now you can use the engine to apply or rollback migrations
///   use _ <- result.try(cigogne.apply(engine))
///   use _ <- result.try(cigogne.rollback(engine))
///
///   // Rest of your application logic
/// }
/// ```
pub fn create_engine(
  config: config.Config,
) -> Result(MigrationEngine, CigogneError) {
  use #(db_data, applied) <- result.try(init_db_and_get_applied(config))
  use files <- result.try(read_migrations(config))
  use applied <- result.try(
    migration.match_migrations(
      applied,
      files,
      config.migrations.no_hash_check |> option.unwrap(False),
    )
    |> result.map_error(MigrationError),
  )
  let non_applied = migration.find_non_applied(files, applied)

  Ok(MigrationEngine(db_data:, applied:, non_applied:, files:, config:))
}

fn init_db_and_get_applied(
  config: config.Config,
) -> Result(#(database.DatabaseData, List(migration.Migration)), CigogneError) {
  {
    use db_data <- result.try(database.init(config))

    use _ <- result.try(database.apply_cigogne_zero(db_data))
    use applied <- result.try(database.get_applied_migrations(db_data))

    Ok(#(db_data, applied))
  }
  |> result.map_error(DatabaseError)
}

/// Read all migration files from the folder specified in the configuration.
/// It is recommended to use `create_engine` instead of this function directly.
/// It can still be useful if you want to read migrations without connecting to the database.
pub fn read_migrations(
  config: config.Config,
) -> Result(List(migration.Migration), CigogneError) {
  let files =
    {
      use priv <- result.try(fs.priv(config.migrations.application_name))
      fs.read_directory(
        priv <> "/" <> config.get_migrations_folder(config.migrations),
      )
    }
    |> result.map_error(FSError)

  use files <- result.try(files)

  let results =
    list.map(files, fn(file) {
      parser_formatter.parse(file) |> result.map_error(ParserError)
    })

  utils.get_results_or_errors(results)
  |> result.map_error(CompoundError)
}

/// Create a new migration file in the folder specified by the configuration with the provided name.
/// Note: Migrations are always created in the `priv/<migrations_folder>` folder.
pub fn new_migration(
  migrations_config: config.MigrationsConfig,
  name: String,
) -> Result(Nil, CigogneError) {
  use new_mig <- result.try(
    migration.new(
      "priv/" <> config.get_migrations_folder(migrations_config),
      name,
      timestamp.system_time(),
    )
    |> result.map_error(MigrationError),
  )

  new_mig
  |> parser_formatter.format()
  |> fs.write_file()
  |> result.map_error(FSError)
  |> result.map(fn(_) {
    io.println("Migration file created : " <> new_mig.path)
  })
}

/// Update the configuration file at `priv/cigogne.toml` with the provided configuration.
/// If the file doesn't exist, it will be created.
/// If it already exists, it will be overwritten.
pub fn update_config(config: config.Config) -> Result(Nil, CigogneError) {
  use _ <- result.map(config.write(config) |> result.map_error(ConfigError))
  io.println("Updated config file at priv/cigogne.toml")
}

/// Apply the next migration that wasn't applied yet.
/// See `create_engine` for an example usage.
/// See `apply_n` to apply multiple migrations at once.
pub fn apply(engine: MigrationEngine) -> Result(Nil, CigogneError) {
  engine.non_applied
  |> list.first()
  |> result.replace_error(NothingToApply)
  |> result.try(fn(mig) { apply_migrations(engine, [mig]) })
}

/// Roll back the last applied migration.
/// See `create_engine` for an example usage.
/// See `rollback_n` to rollback multiple migrations at once.
pub fn rollback(engine: MigrationEngine) -> Result(Nil, CigogneError) {
  engine.applied
  |> list.drop_while(migration.is_zero_migration)
  |> list.last()
  |> result.replace_error(NothingToRollback)
  |> result.try(fn(mig) { rollback_migrations(engine, [mig]) })
}

/// Apply the next `count` migrations.
/// If `count` is less than or equal to 0, this function does nothing.
/// If there is no migration to apply, it returns an error.
/// If there are less than `count` migrations to apply, it applies all of them.
/// 
/// Example usage:
/// ```gleam
/// use engine <- result.try(cigogne.create_engine(config))
/// use _ <- result.try(cigogne.apply_n(engine, 3)) // Apply the next 3 migrations
/// ```
pub fn apply_n(engine: MigrationEngine, count: Int) -> Result(Nil, CigogneError) {
  use <- bool.guard(count <= 0, Ok(Nil))

  let migrations_to_apply =
    engine.non_applied
    |> list.take(count)

  case migrations_to_apply {
    [] -> Error(NothingToApply)
    _ -> apply_migrations(engine, migrations_to_apply)
  }
}

/// Roll back `count` migrations.
/// If `count` is less than or equal to 0, this function does nothing.
/// If there is no migration to rollback, it returns an error.
/// If there are less than `count` migrations to rollback, it rolls all of them back.
/// 
/// Example usage:
/// ```gleam
/// use engine <- result.try(cigogne.create_engine(config))
/// use _ <- result.try(cigogne.rollback_n(engine, 3)) // Rollback the next 3 migrations
/// ```
pub fn rollback_n(
  engine: MigrationEngine,
  count: Int,
) -> Result(Nil, CigogneError) {
  use <- bool.guard(count <= 0, Ok(Nil))

  let migrations_to_rollback =
    engine.applied
    |> list.drop_while(migration.is_zero_migration)
    |> list.reverse()
    |> list.take(count)

  case migrations_to_rollback {
    [] -> Error(NothingToRollback)
    _ -> rollback_migrations(engine, migrations_to_rollback)
  }
}

/// Apply all non-applied migrations.
///
/// Example usage:
/// ```gleam
/// use engine <- result.try(cigogne.create_engine(config))
/// use _ <- result.try(cigogne.apply_all(engine))
/// ```
pub fn apply_all(engine: MigrationEngine) -> Result(Nil, CigogneError) {
  apply_migrations(engine, engine.non_applied)
}

/// Include a library's migrations into your project.
/// This will create a new migration that applies all migrations from the library that haven't been applied yet.
/// This will fail if you haven't added the library to your project.
///
/// Example usage:
/// ```sh
/// gleam add my_lib
/// gleam run -m cigogne include-lib --lib-name my_lib
/// # There will be a new migration file created in priv/migrations with name `<timestamp>-my_lib`
/// ```
pub fn include_lib(
  migration_engine: MigrationEngine,
  lib_name: String,
) -> Result(Nil, CigogneError) {
  use lib_config <- result.try(
    config.get(lib_name) |> result.map_error(ConfigError),
  )

  use lib_migrations <- result.try(read_migrations(lib_config))
  let last_migration_for_dep =
    migration_engine.config.migrations.dependencies |> list.key_find(lib_name)

  let lib_migrations = case last_migration_for_dep {
    Error(_) -> lib_migrations
    Ok(name) ->
      lib_migrations
      |> list.drop_while(fn(mig) { migration.to_fullname(mig) != name })
      |> list.drop(1)
  }

  use merged_mig <- result.try(
    migration.merge(lib_migrations, timestamp.system_time(), lib_name)
    |> result.map_error(MigrationError),
  )
  let merged_mig =
    merged_mig
    |> migration.set_folder(
      "priv/"
      <> config.get_migrations_folder(migration_engine.config.migrations),
    )

  let new_file = parser_formatter.format(merged_mig)
  use _ <- result.try(
    new_file
    |> fs.write_file()
    |> result.map_error(FSError),
  )
  io.println("Created migration at " <> new_file.path)
  let assert Ok(last_migration) = list.last(lib_migrations)

  let new_config =
    config.Config(
      ..migration_engine.config,
      migrations: config.MigrationsConfig(
        ..migration_engine.config.migrations,
        dependencies: {
          migration_engine.config.migrations.dependencies
          |> list.key_set(lib_name, last_migration |> migration.to_fullname())
        },
      ),
    )

  config.write(new_config) |> result.map_error(ConfigError)
}

/// Remove a library's migrations from your project.
/// This will create a new migration that applies all the down migrations from the migrations created by include-lib for this library.
/// This will fail if you haven't included the library yet.
///
/// Example usage:
/// ```sh
/// gleam add my_lib
/// gleam run -m cigogne include-lib --lib-name my_lib
/// gleam run -m cigogne remove-lib --lib-name my_lib
/// # There will be a new migration file created in priv/migrations with name `<timestamp>-remove_my_lib`
/// ```
pub fn remove_lib(
  migration_engine: MigrationEngine,
  lib_name: String,
) -> Result(Nil, CigogneError) {
  let opposite_migrations =
    migration_engine.files
    |> list.filter(fn(mig) { mig.name == lib_name })
    |> list.map(fn(mig) {
      migration.Migration(
        ..mig,
        queries_up: mig.queries_down,
        queries_down: mig.queries_up,
      )
    })
    |> list.reverse()

  use <- bool.guard(
    list.is_empty(opposite_migrations),
    Error(LibNotIncluded(lib_name)),
  )

  use merged_mig <- result.try(
    migration.merge(
      opposite_migrations,
      timestamp.system_time(),
      "remove_" <> lib_name,
    )
    |> result.map_error(MigrationError),
  )
  let merged_mig =
    merged_mig
    |> migration.set_folder(
      "priv/"
      <> config.get_migrations_folder(migration_engine.config.migrations),
    )

  let new_file = parser_formatter.format(merged_mig)
  use _ <- result.try(
    new_file
    |> fs.write_file()
    |> result.map_error(FSError),
  )
  io.println("Created migration at " <> new_file.path)

  let new_config =
    config.Config(
      ..migration_engine.config,
      migrations: config.MigrationsConfig(
        ..migration_engine.config.migrations,
        dependencies: {
          migration_engine.config.migrations.dependencies
          |> list.filter(fn(dep) { dep.0 != lib_name })
        },
      ),
    )

  config.write(new_config) |> result.map_error(ConfigError)
}

/// Apply migrations to the database.
/// It is recommended to use `apply` or `apply_n` instead of this function directly.
/// It can still be useful if you want to apply specific migrations or zero migrations.
/// All migrations will be applied in a single transaction, so either all are applied or none is.
///
/// Be careful though as we don't check if the migration has already been applied or not, see `apply_migration_if_not_applied` for this use case.
pub fn apply_migrations(
  engine: MigrationEngine,
  migrations: List(migration.Migration),
) -> Result(Nil, CigogneError) {
  {
    use transaction <- database.transaction(engine.db_data)
    let db_data =
      database.DatabaseData(..engine.db_data, connection: transaction)
    use migration <- list.try_each(migrations)

    io.println("\nApplying migration " <> migration.to_fullname(migration))
    database.apply_migration_no_transaction(db_data, migration)
  }
  |> result.map_error(DatabaseError)
  |> result.map(fn(_) {
    io.println(
      "Migrations applied:\n\t"
      <> list.map(migrations, migration.to_fullname) |> string.join("\n\t"),
    )
  })
}

/// Roll back migrations from the database.
/// It is recommended to use `rollback` or `rollback_n` instead of this function directly.
/// It can still be useful if you want to roll back specific migrations or a zero migrations.
/// All migrations will be rolled back in a single transaction, so either all are rolled back or none is.
///
/// Be careful though as we don't check if the migration has been applied or not.
pub fn rollback_migrations(
  engine: MigrationEngine,
  migrations: List(migration.Migration),
) -> Result(Nil, CigogneError) {
  {
    use transaction <- database.transaction(engine.db_data)
    let db_data =
      database.DatabaseData(..engine.db_data, connection: transaction)
    use migration <- list.try_each(migrations)

    io.println("\nRolling back migration " <> migration.to_fullname(migration))
    database.rollback_migration_no_transaction(db_data, migration)
  }
  |> result.map_error(DatabaseError)
  |> result.map(fn(_) {
    io.println(
      "Migrations rolled back:\n\t"
      <> list.map(migrations, migration.to_fullname) |> string.join("\n\t"),
    )
  })
}

/// Get all defined migrations in your project.
pub fn get_all_migrations(engine: MigrationEngine) -> List(migration.Migration) {
  engine.files
}

/// Get applied migrations in your project.
pub fn get_applied_migrations(
  engine: MigrationEngine,
) -> List(migration.Migration) {
  engine.applied
}

/// Get non-applied migrations in your project.
pub fn get_non_applied_migrations(
  engine: MigrationEngine,
) -> List(migration.Migration) {
  engine.non_applied
}

fn show(engine: MigrationEngine) -> Nil {
  let migration_names = engine.applied |> list.map(migration.to_fullname)
  let to_apply = engine.non_applied |> list.map(migration.to_fullname)

  io.println(
    "Applied migrations: [\n\t"
    <> migration_names |> string.join(",\n\t")
    <> "\n]\n",
  )
  io.println(
    "Migrations to apply: [\n\t" <> to_apply |> string.join(",\n\t") <> "\n]",
  )
}

fn print_unapplied(migration_engine: MigrationEngine) -> Nil {
  io.print("Unapplied migrations:")

  use unapplied_mig <- list.each(migration_engine.non_applied)

  io.println("\n\n--- == " <> migration.to_fullname(unapplied_mig) <> " ==\n")
  io.println(unapplied_mig.queries_up |> string.join("\n"))
}

/// Print a MigrateError to the standard error stream.
pub fn print_error(error: CigogneError) -> Nil {
  io.println_error(get_error_message(error))
}

fn get_error_message(error: CigogneError) -> String {
  case error {
    CompoundError(errors:) ->
      "Many errors happened ! Here is the list:\n"
      <> errors |> list.map(get_error_message) |> string.join("\n\n")
    ConfigError(error:) ->
      "Configuration error: " <> config.get_error_message(error)
    DatabaseError(error:) ->
      "Database error: " <> database.get_error_message(error)
    FSError(error:) -> "FS error: " <> fs.get_error_message(error)
    LibNotIncluded(name:) ->
      "There were no migrations for library "
      <> name
      <> " !\nDid you include it ?"
    MigrationError(error:) ->
      "Migration error: " <> migration.get_error_message(error)
    NothingToApply -> "There is no migration to apply !\nYou are up-to-date !"
    NothingToRollback -> "There is no migration to rollback !"
    ParserError(error:) ->
      "Parser error: " <> parser_formatter.get_error_message(error)
  }
}

/// Apply a migration to the database if it hasn't been applied.
pub fn apply_migration_if_not_applied(
  engine: MigrationEngine,
  migration: migration.Migration,
) -> Result(Nil, CigogneError) {
  case utils.find_compare(engine.applied, migration, migration.compare) {
    Ok(_) -> Ok(Nil)
    Error(_) -> apply_migrations(engine, [migration])
  }
}
