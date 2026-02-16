import cigogne/config
import cigogne/internal/database
import cigogne/migration
import envoy
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import pog

// Modify these constants to match your local database setup
const db_host = "localhost"

const db_port = 5432

const db_user = "billuc"

const db_password = option.Some("mysecretpassword")

const db_database = "cigogne_test"

const schema = "test"

const migration_table = "migs"

fn db_url() {
  "postgres://"
  <> db_user
  <> case db_password {
    option.Some(password) -> ":" <> password
    option.None -> ""
  }
  <> "@"
  <> db_host
  <> ":"
  <> db_port |> int.to_string
  <> "/"
  <> db_database
}

pub fn init_with_envvar_test() {
  envoy.set("DATABASE_URL", db_url())

  let config =
    config.Config(
      config.EnvVarConfig,
      config.MigrationTableConfig(
        option.Some(schema),
        option.Some(migration_table),
      ),
      config.MigrationsConfig(
        "cigogne",
        option.Some("test/migrations"),
        [],
        option.None,
      ),
    )
  let init_res = database.init(config)

  envoy.unset("DATABASE_URL")
  let assert Ok(init_res) = init_res

  assert init_res |> database.migrations_table_exists |> result.is_ok()
  assert init_res.migrations_table == migration_table
  assert init_res.db_schema == schema
}

pub fn init_with_postgres_envvar_test() {
  envoy.set("PGHOST", db_host)
  envoy.set("PGUSER", db_user)
  envoy.set("PGPASSWORD", db_password |> option.unwrap(""))
  envoy.set("PGDATABASE", db_database)
  envoy.set("PGPORT", db_port |> int.to_string)

  let config =
    config.Config(
      config.EnvVarConfig,
      config.MigrationTableConfig(
        option.Some(schema),
        option.Some(migration_table),
      ),
      config.MigrationsConfig(
        "cigogne",
        option.Some("test/migrations"),
        [],
        option.None,
      ),
    )
  let init_res = database.init(config)

  envoy.unset("PGHOST")
  envoy.unset("PGUSER")
  envoy.unset("PGPASSWORD")
  envoy.unset("PGDATABASE")
  envoy.unset("PGPORT")
  let assert Ok(init_res) = init_res
  assert init_res |> database.migrations_table_exists |> result.is_ok()
  assert init_res.migrations_table == migration_table
  assert init_res.db_schema == schema
}

pub fn init_with_url_test() {
  let config =
    config.Config(
      config.UrlDbConfig(db_url()),
      config.MigrationTableConfig(
        option.Some(schema),
        option.Some(migration_table),
      ),
      config.MigrationsConfig(
        "cigogne",
        option.Some("test/migrations"),
        [],
        option.None,
      ),
    )
  let init_res = database.init(config)

  let assert Ok(init_res) = init_res

  assert init_res.migrations_table == migration_table
  assert init_res.db_schema == schema
}

pub fn init_with_detailed_config_test() {
  let config =
    config.Config(
      config.DetailedDbConfig(
        host: option.Some("localhost"),
        user: option.Some(db_user),
        password: db_password,
        port: option.Some(5432),
        name: option.Some(db_database),
      ),
      config.MigrationTableConfig(
        option.Some(schema),
        option.Some(migration_table),
      ),
      config.MigrationsConfig(
        "cigogne",
        option.Some("test/migrations"),
        [],
        option.None,
      ),
    )
  let init_res = database.init(config)

  let assert Ok(init_res) = init_res

  assert init_res.migrations_table == migration_table
  assert init_res.db_schema == schema
}

pub fn init_with_connection_test() {
  let name = process.new_name("cigogne_test")
  let assert Ok(conf) = pog.url_config(name, db_url())
  let assert Ok(actor) = pog.start(conf)

  let config =
    config.Config(
      config.ConnectionDbConfig(actor.data),
      config.MigrationTableConfig(
        option.Some(schema),
        option.Some(migration_table),
      ),
      config.MigrationsConfig(
        "cigogne",
        option.Some("test/migrations"),
        [],
        option.None,
      ),
    )
  let init_res = database.init(config)
  let assert Ok(init_res) = init_res

  assert init_res.migrations_table == migration_table
  assert init_res.db_schema == schema
}

pub fn migration_table_exists_after_zero_test() {
  let config =
    config.Config(
      config.UrlDbConfig(db_url()),
      config.MigrationTableConfig(
        option.Some(schema),
        option.Some(migration_table),
      ),
      config.MigrationsConfig(
        "cigogne",
        option.Some("test/migrations"),
        [],
        option.None,
      ),
    )
  let assert Ok(init_res) = database.init(config)

  let assert Ok(_) =
    init_res
    |> database.apply_cigogne_zero()

  let assert Ok(exists) = init_res |> database.migrations_table_exists()

  assert exists
}

pub fn apply_get_rollback_migrations_test() {
  let mig_1 =
    migration.create_zero_migration(
      "test1",
      ["create table test.my_table (id serial primary key, name text);"],
      ["drop table test.my_table;"],
    )

  let mig_2 =
    migration.create_zero_migration(
      "test2",
      ["create table test.test_table_2 (id serial primary key);"],
      ["drop table test.test_table_2;"],
    )

  let config =
    config.Config(
      config.UrlDbConfig(db_url()),
      config.MigrationTableConfig(
        option.Some(schema),
        option.Some(migration_table),
      ),
      config.MigrationsConfig(
        "cigogne",
        option.Some("test/migrations"),
        [],
        option.None,
      ),
    )
  let assert Ok(db) = database.init(config)

  let assert Ok(_) = database.apply_cigogne_zero(db)

  let applied_res =
    database.apply_migration(db, mig_1)
    |> result.try(fn(_) { database.apply_migration(db, mig_2) })
    |> result.try(fn(_) { database.get_applied_migrations(db) })

  let assert Ok(applied) = applied_res

  let rb_res =
    database.rollback_migration(db, mig_2)
    |> result.try(fn(_) { database.rollback_migration(db, mig_1) })

  let assert Ok(_) = rb_res

  assert applied |> list.length() == 3
}
