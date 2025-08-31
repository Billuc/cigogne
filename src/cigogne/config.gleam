import gleam/dict
import gleam/erlang/application
import gleam/list
import gleam/option
import gleam/result
import pog
import simplifile
import tom

pub fn get_app_name() -> Result(String, Nil) {
  use content <- result.try(
    simplifile.read("gleam.toml")
    |> result.replace_error(Nil),
  )
  use toml <- result.try(tom.parse(content) |> result.replace_error(Nil))

  tom.get_string(toml, ["name"]) |> result.replace_error(Nil)
}

pub fn parse_toml(application_name: String) -> Config {
  application.priv_directory(application_name)
  |> result.try(read_config_file)
  |> result.map(parse_config_file)
  |> result.unwrap(default_config)
}

fn read_config_file(folder: String) -> Result(String, Nil) {
  let filename = folder <> "/cigogne.toml"
  simplifile.read(filename)
  |> result.replace_error(Nil)
}

pub type Config {
  Config(
    database: DatabaseConfig,
    migration_table: MigrationTableConfig,
    migrations: MigrationsConfig,
  )
}

const default_config = Config(
  default_db_config,
  default_mig_table_config,
  default_migrations_config,
)

fn parse_config_file(content: String) {
  let toml = tom.parse(content) |> result.unwrap(dict.new())

  let database = parse_db_section(toml)
  let migration_table = parse_migration_table_section(toml)
  let migrations = parse_migrations_section(toml)

  Config(database:, migration_table:, migrations:)
}

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

const default_db_config = EnvVarConfig

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

pub type MigrationTableConfig {
  MigrationTableConfig(
    schema: option.Option(String),
    table: option.Option(String),
  )
}

const default_mig_table_config = MigrationTableConfig(option.None, option.None)

fn parse_migration_table_section(
  toml: dict.Dict(String, tom.Toml),
) -> MigrationTableConfig {
  let schema =
    tom.get_string(toml, ["migration-table", "schema"]) |> option.from_result()
  let table =
    tom.get_string(toml, ["migration-table", "table"]) |> option.from_result()
  MigrationTableConfig(schema:, table:)
}

pub type MigrationsConfig {
  MigrationsConfig(
    migration_folder: option.Option(String),
    dependencies: List(String),
  )
}

const default_migrations_config = MigrationsConfig(option.None, [])

fn parse_migrations_section(
  toml: dict.Dict(String, tom.Toml),
) -> MigrationsConfig {
  let migration_folder =
    tom.get_string(toml, ["migrations", "migration_folder"])
    |> option.from_result()
  let dependencies =
    tom.get_array(toml, ["migrations", "dependencies"])
    |> result.replace_error(Nil)
    |> result.try(fn(deps) {
      use dep <- list.try_map(deps)
      case dep {
        tom.String(v) -> Ok(v)
        _ -> Error(Nil)
      }
    })
    |> result.unwrap(default_migrations_config.dependencies)

  MigrationsConfig(migration_folder:, dependencies:)
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

fn merge_migrations_config(
  config: MigrationsConfig,
  to_merge: MigrationsConfig,
) -> MigrationsConfig {
  MigrationsConfig(
    migration_folder: to_merge.migration_folder
      |> option.or(config.migration_folder),
    dependencies: list.append(to_merge.dependencies, config.dependencies),
  )
}
