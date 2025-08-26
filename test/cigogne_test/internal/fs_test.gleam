import cigogne/internal/fs
import cigogne/internal/migrations_utils
import cigogne/types
import gleam/list
import gleam/string
import gleam/time/timestamp
import simplifile

const migrations_folder = "priv_test/migrations"

pub fn simplifile_read_directory_test() {
  let assert Ok(migs) = simplifile.read_directory(migrations_folder)

  assert list.sort(migs, string.compare)
    == ["20240101123246-Test1.sql", "20240922065413-Test2.sql"]
}

pub fn get_migrations_test() {
  let assert Ok(migs) =
    fs.get_migrations(migrations_folder, migration_file_pattern)

  let sorted_migs =
    migs
    |> list.sort(migrations_utils.compare_migrations)

  let assert [first, second, ..] = sorted_migs
  let assert Ok(first_ts) = timestamp.parse_rfc3339("2024-01-01T12:32:46Z")

  assert first.timestamp == first_ts
  assert first.name == "Test1"
  assert first.queries_up
    == ["create table todos(id uuid primary key, title text);"]
  assert first.queries_down == ["drop table todos;"]
  assert string.lowercase(first.sha256)
    == "2455946910aa23ec45cd6df7cf526ab0abaa80ce82b9343c550fa0db8ce65626"

  let assert Ok(second_ts) = timestamp.parse_rfc3339("2024-09-22T06:54:13Z")
  assert second.timestamp == second_ts
  assert second.name == "Test2"
  assert second.queries_up
    == [
      "create table tags(id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY, tag text not null);",
      "alter table todos add column tag integer references tags(id);",
    ]
  assert second.queries_down
    == ["alter table todos drop column tag;", "drop table tags;"]
  assert string.lowercase(second.sha256)
    == "54fc9d43672c5726d2165d33f7a20b596f061de2237f036b937b2afb19d9dcb8"
}

pub fn read_schema_file_test() {
  let assert Ok(result) = fs.read_schema_file("priv_test/sql.schema")
  assert string.starts_with(result, "my test schema")
}

pub fn write_schema_file_test() {
  let path = "priv_test/test.schema"
  let assert Ok(_) = fs.write_schema_file(path, "this is a test")
  let result_read = fs.read_schema_file(path)

  let assert Ok(_) = simplifile.delete(path)

  let assert Ok(result_read) = result_read
  assert result_read == "this is a test"
}

pub fn create_new_migration_file_test() {
  let assert Ok(timestamp) = timestamp.parse_rfc3339("2024-11-17T18:36:41Z")
  let non_existing_folder = migrations_folder <> "/new"

  let _ = simplifile.delete(non_existing_folder)

  let assert Ok(path) =
    fs.create_new_migration_file(
      non_existing_folder,
      timestamp,
      "MyNewMigration",
    )

  assert path == non_existing_folder <> "/20241117183641-MyNewMigration.sql"

  let assert Ok(exists) = simplifile.is_directory(non_existing_folder)
  assert exists
  let assert Ok(content) = simplifile.read(path)

  assert content == "--- migration:up

--- migration:down

--- migration:end"

  let _ = simplifile.delete(non_existing_folder)
}

pub fn create_new_migration_returns_error_if_name_too_long_test() {
  let assert Ok(timestamp) = timestamp.parse_rfc3339("2024-11-17T18:36:41Z")

  let assert Error(err) =
    fs.create_new_migration_file(
      migrations_folder,
      timestamp,
      string.repeat("a", 256),
    )
  assert err == types.NameTooLongError(string.repeat("a", 256))
}
