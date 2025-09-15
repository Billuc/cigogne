import cigogne/internal/fs
import cigogne/internal/utils
import gleam/dict
import gleam/erlang/application
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import pog
import tom

pub type Config {
  Config(
    database: DatabaseConfig,
    migration_table: MigrationTableConfig,
    migrations: MigrationsConfig,
  )
}

pub const default_config = Config(
  default_db_config,
  default_mig_table_config,
  default_migrations_config,
)

pub type DatabaseConfig {
  UrlDbConfig(url: String)
  DetailedDbConfig(
    host: option.Option(String),
    user: option.Option(String),
    password: option.Option(String),
    port: option.Option(Int),
    name: option.Option(String),
  )
  EnvVarConfig
  ConnectionDbConfig(connection: pog.Connection)
}

pub const default_db_config = EnvVarConfig

pub type MigrationTableConfig {
  MigrationTableConfig(
    schema: option.Option(String),
    table: option.Option(String),
  )
}

pub const default_mig_table_config = MigrationTableConfig(
  option.None,
  option.None,
)

pub type MigrationsConfig {
  MigrationsConfig(
    application_name: String,
    migration_folder: option.Option(String),
    dependencies: List(#(String, String)),
  )
}

pub const default_migrations_config = MigrationsConfig(
  "cigogne",
  option.None,
  [],
)

const default_migrations_folder = "migrations"

pub type ConfigError {
  AppNameError
  AppNotFound(name: String)
  ConfigFileNotFound(path: String)
  FSError(error: fs.FSError)
}

pub fn get_app_name() -> Result(String, ConfigError) {
  use file <- utils.try_or(fs.read_file("gleam.toml"), AppNameError)
  use toml <- utils.try_or(tom.parse(file.content), AppNameError)

  tom.get_string(toml, ["name"])
  |> result.replace_error(AppNameError)
}

pub fn get(application_name: String) -> Result(Config, ConfigError) {
  use priv_dir <- result.map(
    application.priv_directory(application_name)
    |> result.replace_error(AppNotFound(application_name)),
  )
  let filename = priv_dir <> "/cigogne.toml"

  fs.read_file(filename)
  |> result.replace_error(ConfigFileNotFound(filename))
  |> result.map(fn(file) { parse_config_file(file.content, application_name) })
  |> result.unwrap(default_config)
}

pub fn write(config: Config) -> Result(Nil, ConfigError) {
  fs.create_directory("priv")
  |> result.try(fn(_) {
    fs.write_file(fs.File("priv/cigogne.toml", print_config(config)))
  })
  |> result.map_error(FSError)
}

fn parse_config_file(content: String, application_name: String) -> Config {
  let toml = tom.parse(content) |> result.unwrap(dict.new())

  let database = parse_db_section(toml)
  let migration_table = parse_migration_table_section(toml)
  let migrations = parse_migrations_section(toml, application_name)

  Config(database:, migration_table:, migrations:)
}

fn parse_db_section(toml: dict.Dict(String, tom.Toml)) -> DatabaseConfig {
  tom.get_string(toml, ["database", "url"])
  |> result.map(UrlDbConfig)
  |> result.unwrap({
    let host =
      tom.get_string(toml, ["database", "host"]) |> option.from_result()
    let user =
      tom.get_string(toml, ["database", "user"]) |> option.from_result()
    let password =
      tom.get_string(toml, ["database", "password"]) |> option.from_result()
    let port = tom.get_int(toml, ["database", "port"]) |> option.from_result()
    let name =
      tom.get_string(toml, ["database", "name"]) |> option.from_result()

    case host, user, password, port, name {
      option.None, option.None, option.None, option.None, option.None ->
        EnvVarConfig
      _, _, _, _, _ -> DetailedDbConfig(host:, user:, password:, port:, name:)
    }
  })
}

fn parse_migration_table_section(
  toml: dict.Dict(String, tom.Toml),
) -> MigrationTableConfig {
  let schema =
    tom.get_string(toml, ["migration-table", "schema"]) |> option.from_result()
  let table =
    tom.get_string(toml, ["migration-table", "table"]) |> option.from_result()
  MigrationTableConfig(schema:, table:)
}

fn parse_migrations_section(
  toml: dict.Dict(String, tom.Toml),
  application_name: String,
) -> MigrationsConfig {
  let migration_folder =
    tom.get_string(toml, ["migrations", "migration_folder"])
    |> option.from_result()
  let dependencies =
    tom.get_table(toml, ["migrations", "dependencies"])
    |> result.replace_error(Nil)
    |> result.try(fn(deps) {
      use dep <- list.try_map(deps |> dict.to_list())
      case dep {
        #(k, tom.String(v)) -> Ok(#(k, v))
        _ -> Error(Nil)
      }
    })
    |> result.unwrap(default_migrations_config.dependencies)

  MigrationsConfig(application_name:, migration_folder:, dependencies:)
}

pub fn merge(config: Config, to_merge: Config) -> Config {
  Config(
    database: merge_database_config(config.database, to_merge.database),
    migration_table: merge_migration_table_config(
      config.migration_table,
      to_merge.migration_table,
    ),
    migrations: merge_migrations_config(config.migrations, to_merge.migrations),
  )
}

fn merge_database_config(config: DatabaseConfig, to_merge: DatabaseConfig) {
  case config, to_merge {
    c, EnvVarConfig -> c
    DetailedDbConfig(host1, user1, pw1, port1, name1),
      DetailedDbConfig(host2, user2, pw2, port2, name2)
    ->
      DetailedDbConfig(
        host: host2 |> option.or(host1),
        user: user2 |> option.or(user1),
        password: pw2 |> option.or(pw1),
        port: port2 |> option.or(port1),
        name: name2 |> option.or(name1),
      )
    _, c -> c
  }
}

fn merge_migration_table_config(
  config: MigrationTableConfig,
  to_merge: MigrationTableConfig,
) -> MigrationTableConfig {
  MigrationTableConfig(
    schema: to_merge.schema |> option.or(config.schema),
    table: to_merge.table |> option.or(to_merge.table),
  )
}

pub fn merge_migrations_config(
  config: MigrationsConfig,
  to_merge: MigrationsConfig,
) -> MigrationsConfig {
  MigrationsConfig(
    application_name: to_merge.application_name,
    migration_folder: to_merge.migration_folder
      |> option.or(config.migration_folder),
    dependencies: list.append(to_merge.dependencies, config.dependencies),
  )
}

pub fn print_config(config: Config) -> String {
  let db_str = print_db_config(config.database)
  let mig_table_str = print_migration_table_config(config.migration_table)
  let mig_str = print_migrations_config(config.migrations)
  db_str <> mig_table_str <> mig_str
}

fn print_db_config(config: DatabaseConfig) -> String {
  let db_str =
    "# This section will be overridden by eventual users of the library\n"
    <> "[database]\n"
    <> "# If url is defined, it is used to connect to the database\n"

  let db_str = case config {
    UrlDbConfig(url:) -> db_str <> "url = \"" <> url <> "\"\n\n"
    _ -> db_str <> "# url = \"\"\n\n"
  }

  let db_str =
    db_str
    <> "# If other data in this section is defined, it is used to connect\n"
    <> "# Otherwise, we fallback to the DATABASE_URL environment variable\n"

  case config {
    DetailedDbConfig(host:, user:, password:, port:, name:) -> {
      let host_str = print_option_string(host, "host", "localhost")
      let user_str = print_option_string(user, "user", "postgres")
      let password_str = print_option_string(password, "password", "postgres")
      let port_str = print_option_int(port, "port", 5432)
      let name_str = print_option_string(name, "name", "postgres")

      db_str
      <> host_str
      <> user_str
      <> "# /!\\ It is not recommended to have your password there\n"
      <> password_str
      <> port_str
      <> name_str
      <> "\n"
    }
    _ ->
      db_str
      <> "# host = \"localhost\"\n"
      <> "# user = \"postgres\"\n"
      <> "# /!\\ It is not recommended to have your password there\n"
      <> "# password = \"postgres\"\n"
      <> "# port = 5432\n"
      <> "# name = \"postgres\"\n\n"
  }
}

fn print_migration_table_config(config: MigrationTableConfig) -> String {
  let mig_table_str =
    "# This section will be overridden by eventual users of the library\n"
    <> "[migration-table]\n"

  let schema_str = print_option_string(config.schema, "schema", "public")
  let table_str = print_option_string(config.table, "table", "migrations")

  mig_table_str <> schema_str <> table_str <> "\n"
}

fn print_migrations_config(config: MigrationsConfig) -> String {
  let mig_str = "[migrations]\n"

  let mig_folder_str =
    print_option_string(
      config.migration_folder,
      "migration_folder",
      "migrations",
    )

  let dependencies_str =
    "\n[migrations.dependencies]\n"
    <> list.map(config.dependencies, fn(dep) {
      dep.0 <> " = \"" <> dep.1 <> "\""
    })
    |> string.join("\n")

  mig_str <> mig_folder_str <> dependencies_str <> "\n"
}

fn print_option_string(
  value: option.Option(String),
  name: String,
  default: String,
) -> String {
  case value {
    option.Some(v) -> name <> " = \"" <> v <> "\"\n"
    option.None -> "# " <> name <> " = \"" <> default <> "\"\n"
  }
}

fn print_option_int(
  value: option.Option(Int),
  name: String,
  default: Int,
) -> String {
  case value {
    option.Some(v) -> name <> " = " <> int.to_string(v) <> "\n"
    option.None -> "# " <> name <> " = " <> int.to_string(default) <> "\n"
  }
}

pub fn get_migrations_folder(migrations_config: MigrationsConfig) -> String {
  migrations_config.migration_folder |> option.unwrap(default_migrations_folder)
}

pub fn get_error_message(error: ConfigError) {
  case error {
    AppNameError ->
      "Couldn't get the application's name !\nAre you in a folder with a gleam.toml file ?"
    AppNotFound(name:) ->
      "Could not find an application with name "
      <> name
      <> "\nDid you correctly add it to your project ?"
    ConfigFileNotFound(path:) ->
      "Could not find this project's config file.\nNote: it should be at "
      <> path
    FSError(error:) -> "FS error: " <> fs.get_error_message(error)
  }
}
