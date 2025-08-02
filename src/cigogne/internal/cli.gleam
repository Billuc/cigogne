import cigogne/internal/cli_lib
import gleam/option

pub type CliActions {
  MigrateUp(options: ConfigOptions, count: Int)
  MigrateDown(options: ConfigOptions, count: Int)
  ShowMigrations(options: ConfigOptions)
  MigrateToLast(options: ConfigOptions)
  NewMigration(folder: option.Option(String), name: String)
}

pub type ConfigOptions {
  ConfigOptions(
    db_url: option.Option(String),
    db_host: option.Option(String),
    db_user: option.Option(String),
    db_password: option.Option(String),
    db_port: option.Option(Int),
    db_name: option.Option(String),
    schema: option.Option(String),
    migration_table: option.Option(String),
    gen_schema: Bool,
    schema_filename: option.Option(String),
    migration_folder: option.Option(String),
    migration_pattern: option.Option(String),
  )
}

pub fn get_action(args: List(String)) {
  cli_lib.command("cigogne")
  |> cli_lib.with_description("Cigogne CLI")
  |> cli_lib.add_action(migrate_up_action())
  |> cli_lib.add_action(migrate_down_action())
  |> cli_lib.add_action(new_migration_action())
  |> cli_lib.add_action(show_migrations_action())
  |> cli_lib.add_action(migrate_to_last_action())
  |> cli_lib.run(args)
}

fn migrate_up_action() -> cli_lib.Action(CliActions) {
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
      use config <- cli_lib.map_action(config_decoder())
      MigrateUp(config, count |> option.unwrap(1))
    },
  )
}

fn migrate_down_action() -> cli_lib.Action(CliActions) {
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
      use config <- cli_lib.map_action(config_decoder())
      MigrateDown(config, count |> option.unwrap(1))
    },
  )
}

fn show_migrations_action() -> cli_lib.Action(CliActions) {
  cli_lib.create_action(
    ["show"],
    "Show the last / currently applied migration",
    {
      use config <- cli_lib.map_action(config_decoder())
      ShowMigrations(config)
    },
  )
}

fn migrate_to_last_action() -> cli_lib.Action(CliActions) {
  cli_lib.create_action(["last"], "Apply all non-applied migrations", {
    use config <- cli_lib.map_action(config_decoder())
    MigrateToLast(config)
  })
}

fn new_migration_action() -> cli_lib.Action(CliActions) {
  cli_lib.create_action(
    ["new"],
    "Create a new migration file (by default created in priv/migrations)",
    {
      use folder <- cli_lib.flag(
        "folder",
        ["F"],
        "FOLDER",
        "Folder to store the migration (default: priv/migrations)",
        cli_lib.string,
      )
      use name <- cli_lib.flag(
        "name",
        ["N"],
        "NAME",
        "Name of the migration file",
        cli_lib.required(cli_lib.string, ""),
      )
      cli_lib.options(NewMigration(folder, name))
    },
  )
}

fn config_decoder() -> cli_lib.ActionDecoder(ConfigOptions) {
  use db_url <- cli_lib.flag(
    "url",
    [],
    "URL",
    "Database URL, if specified replaces other DB parameters",
    cli_lib.string,
  )
  use db_host <- cli_lib.flag(
    "host",
    ["H"],
    "HOST",
    "Database host (default: localhost)",
    cli_lib.string,
  )
  use db_user <- cli_lib.flag(
    "user",
    ["U"],
    "USER",
    "Database user (default: postgres)",
    cli_lib.string,
  )
  use db_password <- cli_lib.flag(
    "password",
    ["W"],
    "PASSWD",
    "Database password (default: postgres)",
    cli_lib.string,
  )
  use db_port <- cli_lib.flag(
    "port",
    ["P"],
    "PORT",
    "Database port (default: 5432)",
    cli_lib.int,
  )
  use db_name <- cli_lib.flag(
    "database",
    ["D"],
    "NAME",
    "Database name (default: postgres)",
    cli_lib.string,
  )
  use schema <- cli_lib.flag(
    "schema",
    ["S"],
    "SCHEMA",
    "Database schema to use (default: public)",
    cli_lib.string,
  )
  use migration_table <- cli_lib.flag(
    "migration-table",
    ["T"],
    "TABLE",
    "Migration table name (default: _migrations)",
    cli_lib.string,
  )
  use no_gen_schema <- cli_lib.flag(
    "no-gen-schema",
    ["G"],
    "",
    "Disable generation schema file (default: false)",
    cli_lib.bool,
  )
  use schema_filename <- cli_lib.flag(
    "schema-filename",
    ["F"],
    "FILENAME",
    "Schema filename to generate (default: ./sql.schema)",
    cli_lib.string,
  )
  use migration_folder <- cli_lib.flag(
    "migration-folder",
    ["M"],
    "FOLDER",
    "Folder to store migrations (default: priv/migrations)",
    cli_lib.string,
  )
  use migration_pattern <- cli_lib.flag(
    "migration-pattern",
    ["m"],
    "PATTERN",
    "Pattern to find migration scripts (default: *.sql)",
    cli_lib.string,
  )

  cli_lib.options(ConfigOptions(
    db_url:,
    db_host:,
    db_user:,
    db_password:,
    db_port:,
    db_name:,
    schema:,
    migration_table:,
    gen_schema: !no_gen_schema,
    schema_filename:,
    migration_folder:,
    migration_pattern:,
  ))
}
