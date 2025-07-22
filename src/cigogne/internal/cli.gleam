import argv
import cigogne/internal/cli_lib
import cigogne/types
import gleam/option

pub type CliActions {
  MigrateUp(options: ConfigOptions)
  MigrateDown(url: String, generate_schema: Bool)
  Show
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
    // Use envvar
  )
}

pub fn main() {
  let action =
    cli_lib.command("cigogne")
    |> cli_lib.with_description("Cigogne CLI")
    |> cli_lib.add_action(migrate_up_action())
    |> cli_lib.run(argv.load().arguments)

  echo action
}

fn migrate_up_action() -> cli_lib.Action(CliActions) {
  cli_lib.create_action(["migrate", "up"], "Apply all pending migrations", {
    use config <- cli_lib.map_action(config_decoder())
    MigrateUp(config)
  })
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

  cli_lib.options(ConfigOptions(
    db_url:,
    db_host:,
    db_user:,
    db_password:,
    db_port:,
    db_name:,
    schema:,
    migration_table:,
    gen_schema:,
    schema_filename:,
    migration_folder:,
    migration_pattern:,
  ))
}
