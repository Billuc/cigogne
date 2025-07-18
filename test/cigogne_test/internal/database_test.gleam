import cigogne/internal/database
import cigogne/internal/migrations_utils
import cigogne/types
import envoy
import gleam/erlang/process
import gleam/list
import gleam/option
import gleam/result
import pog

// Modify these constants to match your local database setup
const db_user = "lbillaud"

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
  <> "@localhost:5432/"
  <> db_database
}

pub fn init_with_envvar_test() {
  envoy.set("DATABASE_URL", db_url())

  let init_res = database.init(types.EnvVarConfig, schema, migration_table)

  envoy.unset("DATABASE_URL")

  let assert Ok(init_res) = init_res

  assert init_res.db_url == option.Some(db_url())
  assert init_res.migrations_table_name == migration_table
  assert init_res.schema == schema
}

pub fn init_with_url_test() {
  let init_res =
    database.init(types.UrlConfig(db_url()), schema, migration_table)

  let assert Ok(init_res) = init_res

  assert init_res.db_url == option.Some(db_url())
  assert init_res.migrations_table_name == migration_table
  assert init_res.schema == schema
}

pub fn init_with_pog_config_test() {
  let name = process.new_name("cigogne_test")
  let init_res =
    database.init(
      types.PogConfig(
        pog.default_config(name)
        |> pog.host("localhost")
        |> pog.port(5432)
        |> pog.user(db_user)
        |> pog.database(db_database),
      ),
      schema,
      migration_table,
    )

  let assert Ok(init_res) = init_res

  assert init_res.db_url == option.None
  assert init_res.migrations_table_name == migration_table
  assert init_res.schema == schema
}

pub fn init_with_connection_test() {
  let name = process.new_name("cigogne_test")
  let assert Ok(conf) = pog.url_config(name, db_url())
  let assert Ok(actor) = pog.start(conf)

  let init_res =
    database.init(types.ConnectionConfig(actor.data), schema, migration_table)
  let assert Ok(init_res) = init_res

  assert init_res.db_url == option.None
  assert init_res.migrations_table_name == migration_table
  assert init_res.schema == schema
}

pub fn migration_table_exists_after_zero_test() {
  let assert Ok(init_res) =
    database.init(types.UrlConfig(db_url()), schema, migration_table)

  let assert Ok(_) =
    init_res
    |> database.apply_cigogne_zero()

  let assert Ok(exists) = init_res |> database.migrations_table_exists()

  assert exists
}

pub fn apply_get_rollback_migrations_test() {
  let mig_1 =
    migrations_utils.create_zero_migration(
      "test1",
      ["create table test.my_table (id serial primary key, name text);"],
      ["drop table test.my_table;"],
    )

  let mig_2 =
    migrations_utils.create_zero_migration(
      "test2",
      ["create table test.test_table_2 (id serial primary key);"],
      ["drop table test.test_table_2;"],
    )

  let assert Ok(db) =
    database.init(types.UrlConfig(db_url()), schema, migration_table)

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
