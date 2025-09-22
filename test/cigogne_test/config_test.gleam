import cigogne/config
import gleam/option

pub fn get_app_name_test() {
  let result = config.get_app_name()
  assert result == Ok("cigogne")
}

pub fn get_config_test() {
  let result = config.get("cigogne")
  assert result == Ok(config.default_config)
}

pub fn merge_config_test() {
  let config_from_args =
    config.Config(
      database: config.DetailedDbConfig(
        host: option.None,
        port: option.Some(5433),
        user: option.Some("admin"),
        password: option.None,
        name: option.Some("mydb"),
      ),
      migration_table: config.MigrationTableConfig(
        schema: option.Some("test"),
        table: option.Some("_migrations"),
      ),
      migrations: config.MigrationsConfig(
        application_name: "cigogne",
        migration_folder: option.None,
        dependencies: [],
        no_hash_check: option.Some(False),
      ),
    )
  let config_from_file =
    config.Config(
      database: config.DetailedDbConfig(
        host: option.Some("192.168.10.11"),
        port: option.Some(5432),
        user: option.Some("myuser"),
        password: option.None,
        name: option.Some("testdb"),
      ),
      migration_table: config.MigrationTableConfig(
        schema: option.Some("public"),
        table: option.Some("my_migrations"),
      ),
      migrations: config.MigrationsConfig(
        application_name: "cigogne",
        migration_folder: option.Some("test/migrations"),
        dependencies: [
          #("dep1", "20250915152222-AddUsers"),
          #("dep2", "20250915152323-AddSomeConstraint"),
        ],
        no_hash_check: option.None,
      ),
    )

  let merged_config = config.merge(config_from_file, config_from_args)

  assert merged_config
    == config.Config(
      database: config.DetailedDbConfig(
        host: option.Some("192.168.10.11"),
        port: option.Some(5433),
        user: option.Some("admin"),
        password: option.None,
        name: option.Some("mydb"),
      ),
      migration_table: config.MigrationTableConfig(
        schema: option.Some("test"),
        table: option.Some("_migrations"),
      ),
      migrations: config.MigrationsConfig(
        application_name: "cigogne",
        migration_folder: option.Some("test/migrations"),
        dependencies: [
          #("dep1", "20250915152222-AddUsers"),
          #("dep2", "20250915152323-AddSomeConstraint"),
        ],
        no_hash_check: option.Some(False),
      ),
    )
}

pub fn print_config_test() {
  let my_config =
    config.Config(
      database: config.DetailedDbConfig(
        host: option.Some("192.168.10.11"),
        port: option.Some(5432),
        user: option.Some("admin"),
        password: option.Some("adminpassword"),
        name: option.Some("mydb"),
      ),
      migration_table: config.MigrationTableConfig(
        schema: option.Some("test"),
        table: option.Some("my_migrations"),
      ),
      migrations: config.MigrationsConfig(
        application_name: "cigogne",
        migration_folder: option.Some("custom_migrations"),
        dependencies: [
          #("dep1", "20250915152222-AddUsers"),
          #("dep2", "20250915152323-AddSomeConstraint"),
        ],
        no_hash_check: option.Some(False),
      ),
    )

  let result = config.print(my_config)

  assert result
    == "# This section will be overridden by eventual users of the library
[database]
# If url is defined, it is used to connect to the database
# url = \"\"

# If other data in this section is defined, it is used to connect
# Otherwise, we fallback to the DATABASE_URL environment variable
host = \"192.168.10.11\"
user = \"admin\"
# /!\\ It is not recommended to have your password there
password = \"adminpassword\"
port = 5432
name = \"mydb\"

# This section will be overridden by eventual users of the library
[migration-table]
schema = \"test\"
table = \"my_migrations\"

[migrations]
migration_folder = \"custom_migrations\"

[migrations.dependencies]
dep1 = \"20250915152222-AddUsers\"
dep2 = \"20250915152323-AddSomeConstraint\"
"
}

pub fn get_migrations_folder_test() {
  let test_config = config.default_migrations_config
  let test_config_with_folder =
    config.MigrationsConfig(
      application_name: "cigogne",
      migration_folder: option.Some("custom_migrations"),
      dependencies: [],
      no_hash_check: option.None,
    )

  assert config.get_migrations_folder(test_config) == "migrations"
  assert config.get_migrations_folder(test_config_with_folder)
    == "custom_migrations"
}
