import cigogne
import cigogne/config
import gleam/option
import gleam/string
import gleam/time/timestamp
import gleeunit
import simplifile

pub fn main() {
  gleeunit.main()
}

pub fn simplifile_test() {
  let priv_test_folder = "priv/test"
  let test_migrations_folder = priv_test_folder <> "/test_migrations"

  let assert Ok(True) = simplifile.is_directory(priv_test_folder)
  let assert Ok(False) = simplifile.is_directory(test_migrations_folder)
}

pub fn read_migrations_test() {
  let config =
    config.Config(
      ..config.default_config,
      migrations: config.MigrationsConfig(
        application_name: "cigogne",
        migration_folder: option.Some("test/migrations"),
        dependencies: [],
      ),
    )

  let assert Ok(migrations) = cigogne.read_migrations(config)
  let assert Ok(ts1) = timestamp.parse_rfc3339("2024-01-01T12:32:46Z")
  let assert Ok(ts2) = timestamp.parse_rfc3339("2024-09-22T06:54:13Z")

  let assert [mig1, mig2] = migrations |> echo

  assert mig1.path
    |> string.ends_with("test/migrations/20240101123246-Test1.sql")
  assert mig1.timestamp == ts1
  assert mig1.name == "Test1"
  assert mig1.queries_up
    == ["create table todos(id uuid primary key, title text);"]
  assert mig1.queries_down == ["drop table todos;"]
  assert mig1.sha256
    == "2455946910AA23EC45CD6DF7CF526AB0ABAA80CE82B9343C550FA0DB8CE65626"

  assert mig2.path
    |> string.ends_with("test/migrations/20240922065413-Test2.sql")
  assert mig2.timestamp == ts2
  assert mig2.name == "Test2"
  assert mig2.queries_up
    == [
      "create table tags(id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY, tag text not null);",
      "alter table todos add column tag integer references tags(id);",
    ]
  assert mig2.queries_down
    == ["alter table todos drop column tag;", "drop table tags;"]
  assert mig2.sha256
    == "54FC9D43672C5726D2165D33F7A20B596F061DE2237F036B937B2AFB19D9DCB8"
}
