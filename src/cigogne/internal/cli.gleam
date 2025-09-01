import cigogne/config
import cigogne/internal/cli_lib
import gleam/option
import gleam/result

pub type CliActions {
  MigrateUp(config: config.Config, count: Int)
  MigrateDown(config: config.Config, count: Int)
  ShowMigrations(config: config.Config)
  MigrateToLast(config: config.Config)
  NewMigration(migrations: config.MigrationsConfig, name: String)
}

pub fn get_action(args: List(String)) -> Result(CliActions, Nil) {
  use application_name <- result.try(config.get_app_name())

  cli_lib.command("cigogne")
  |> cli_lib.with_description("Cigogne CLI")
  |> cli_lib.add_action(migrate_up_action(application_name))
  |> cli_lib.add_action(migrate_down_action(application_name))
  |> cli_lib.add_action(new_migration_action(application_name))
  |> cli_lib.add_action(show_migrations_action(application_name))
  |> cli_lib.add_action(migrate_to_last_action(application_name))
  |> cli_lib.run(args)
}

fn migrate_up_action(application_name: String) -> cli_lib.Action(CliActions) {
  cli_lib.create_action(
    ["up"],
    "Migrate up one version / Apply one migration",
    {
      use count <- cli_lib.flag(
        "count",
        ["n"],
        "N",
        "Number of migrations to apply",
        cli_lib.int,
      )
      use config <- cli_lib.map_action(config_decoder(application_name))
      MigrateUp(config, count |> option.unwrap(1))
    },
  )
}

fn migrate_down_action(application_name: String) -> cli_lib.Action(CliActions) {
  cli_lib.create_action(
    ["down"],
    "Migrate down one version / Rollback one migration",
    {
      use count <- cli_lib.flag(
        "count",
        ["n"],
        "N",
        "Number of migrations to rollback",
        cli_lib.int,
      )
      use config <- cli_lib.map_action(config_decoder(application_name))
      MigrateDown(config, count |> option.unwrap(1))
    },
  )
}

fn show_migrations_action(
  application_name: String,
) -> cli_lib.Action(CliActions) {
  cli_lib.create_action(
    ["show"],
    "Show the last / currently applied migration",
    {
      use config <- cli_lib.map_action(config_decoder(application_name))
      ShowMigrations(config)
    },
  )
}

fn migrate_to_last_action(
  application_name: String,
) -> cli_lib.Action(CliActions) {
  cli_lib.create_action(["up-all"], "Apply all non-applied migrations", {
    use config <- cli_lib.map_action(config_decoder(application_name))
    MigrateToLast(config)
  })
}

fn new_migration_action(application_name: String) -> cli_lib.Action(CliActions) {
  cli_lib.create_action(
    ["new"],
    "Create a new migration file (by default created in priv/migrations)",
    {
      use migrations <- cli_lib.then_action(migrations_config_decoder(
        application_name,
      ))
      use name <- cli_lib.flag(
        "name",
        ["N"],
        "NAME",
        "Name of the migration file",
        cli_lib.required(cli_lib.string, ""),
      )
      cli_lib.options(NewMigration(migrations, name))
    },
  )
}

fn config_decoder(
  application_name: String,
) -> cli_lib.ActionDecoder(config.Config) {
  use database <- cli_lib.then_action(database_config_decoder())
  use migration_table <- cli_lib.then_action(migration_table_config_decoder())
  use migrations <- cli_lib.map_action(migrations_config_decoder(
    application_name,
  ))

  config.Config(database:, migration_table:, migrations:)
}

fn database_config_decoder() -> cli_lib.ActionDecoder(config.DatabaseConfig) {
  use url <- cli_lib.flag(
    "url",
    [],
    "URL",
    "Database URL, if specified replaces other DB parameters",
    cli_lib.string,
  )
  use host <- cli_lib.flag(
    "host",
    ["H"],
    "HOST",
    "Database host (default: localhost)",
    cli_lib.string,
  )
  use user <- cli_lib.flag(
    "user",
    ["U"],
    "USER",
    "Database user (default: postgres)",
    cli_lib.string,
  )
  use password <- cli_lib.flag(
    "password",
    ["W"],
    "PASSWD",
    "Database password (default: postgres)",
    cli_lib.string,
  )
  use port <- cli_lib.flag(
    "port",
    ["P"],
    "PORT",
    "Database port (default: 5432)",
    cli_lib.int,
  )
  use name <- cli_lib.flag(
    "database",
    ["D"],
    "NAME",
    "Database name (default: postgres)",
    cli_lib.string,
  )

  cli_lib.options(case url {
    option.None ->
      config.DetailedDbConfig(host:, user:, password:, port:, name:)
    option.Some(url) -> config.UrlDbConfig(url:)
  })
}

fn migration_table_config_decoder() -> cli_lib.ActionDecoder(
  config.MigrationTableConfig,
) {
  use schema <- cli_lib.flag(
    "schema",
    ["S"],
    "SCHEMA",
    "Database schema to use (default: public)",
    cli_lib.string,
  )
  use table <- cli_lib.flag(
    "migrations-table",
    ["T"],
    "TABLE",
    "Migrations table name (default: _migrations)",
    cli_lib.string,
  )

  cli_lib.options(config.MigrationTableConfig(schema:, table:))
}

fn migrations_config_decoder(
  application_name: String,
) -> cli_lib.ActionDecoder(config.MigrationsConfig) {
  use migration_folder <- cli_lib.flag(
    "migration-folder",
    ["M"],
    "FOLDER",
    "Folder to store migrations in the priv folder (default: migrations)",
    cli_lib.string,
  )

  cli_lib.options(
    config.MigrationsConfig(
      application_name:,
      migration_folder:,
      dependencies: [],
    ),
  )
}
