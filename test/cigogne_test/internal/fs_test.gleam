import cigogne/fs
import gleam/list
import gleam/string
import simplifile

const migrations_folder = "test/migrations"

pub fn simplifile_read_directory_test() {
  let assert Ok(migs) = simplifile.read_directory("priv/" <> migrations_folder)

  assert list.sort(migs, string.compare)
    == ["20240101123246-Test1.sql", "20240922065413-Test2.sql"]
}

pub fn priv_test() {
  let assert Ok(path) = fs.priv("cigogne")
  assert path |> string.ends_with("cigogne/priv")
}

pub fn read_file_test() {
  let file = "priv/cigogne.toml"
  let assert Ok(file) = fs.read_file(file)

  assert file.path |> string.ends_with("priv/cigogne.toml")
  assert file.content |> string.contains("[migrations]")
}

pub fn create_directory_test() {
  let non_existing_folder = migrations_folder <> "/new"
  let path = "priv/" <> non_existing_folder

  let _ = simplifile.delete(path)
  let res_create = fs.create_directory(path)
  let exists_res = simplifile.is_directory(path)
  let assert Ok(_) = simplifile.delete(path)

  assert res_create == Ok(Nil)
  assert exists_res == Ok(True)
}

pub fn write_file_test() {
  let non_existing_file = "priv/new_file.txt"
  let file = fs.File(non_existing_file, "Hello, World!")

  let _ = simplifile.delete(non_existing_file)
  let res_write = fs.write_file(file)
  let exists_res = simplifile.is_file(non_existing_file)
  let assert Ok(content) = simplifile.read(non_existing_file)
  let assert Ok(_) = simplifile.delete(non_existing_file)

  assert res_write == Ok(Nil)
  assert exists_res == Ok(True)
  assert content == "Hello, World!"
}

pub fn read_directory_test() {
  let assert Ok(files) = fs.read_directory("priv/" <> migrations_folder)

  let assert [first, second] = files

  assert first.path |> string.ends_with("20240101123246-Test1.sql")
  assert first.content
    |> string.contains("create table todos(id uuid primary key, title text);")

  assert second.path |> string.ends_with("20240922065413-Test2.sql")
  assert second.content
    |> string.contains(
      "create table tags(id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY, tag text not null);",
    )
}
// pub fn get_migrations_test() {
//   let config =
//     config.MigrationsConfig("cigogne", option.Some(migrations_folder), [])
//   let assert Ok(migs) = fs.get_migrations(config)
//
//   let sorted_migs =
//     migs
//     |> list.sort(migrations_utils.compare_migrations)
//
//   let assert [first, second, ..] = sorted_migs
//   let assert Ok(first_ts) = timestamp.parse_rfc3339("2024-01-01T12:32:46Z")
//
//   assert first.timestamp == first_ts
//   assert first.name == "Test1"
//   assert first.queries_up
//     == ["create table todos(id uuid primary key, title text);"]
//   assert first.queries_down == ["drop table todos;"]
//   assert string.lowercase(first.sha256)
//     == "2455946910aa23ec45cd6df7cf526ab0abaa80ce82b9343c550fa0db8ce65626"
//
//   let assert Ok(second_ts) = timestamp.parse_rfc3339("2024-09-22T06:54:13Z")
//   assert second.timestamp == second_ts
//   assert second.name == "Test2"
//   assert second.queries_up
//     == [
//       "create table tags(id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY, tag text not null);",
//       "alter table todos add column tag integer references tags(id);",
//     ]
//   assert second.queries_down
//     == ["alter table todos drop column tag;", "drop table tags;"]
//   assert string.lowercase(second.sha256)
//     == "54fc9d43672c5726d2165d33f7a20b596f061de2237f036b937b2afb19d9dcb8"
// }
//
// pub fn create_new_migration_file_test() {
//   let assert Ok(timestamp) = timestamp.parse_rfc3339("2024-11-17T18:36:41Z")
//   let non_existing_folder = migrations_folder <> "/new"
//   let config =
//     config.MigrationsConfig("cigogne", option.Some(non_existing_folder), [])
//
//   let _ = simplifile.delete(non_existing_folder)
//
//   let assert Ok(path) =
//     fs.create_new_migration_file(config, timestamp, "MyNewMigration")
//
//   assert path
//     |> string.ends_with(
//       "priv/" <> non_existing_folder <> "/20241117183641-MyNewMigration.sql",
//     )
//
//   let assert Ok(exists) =
//     simplifile.is_directory("priv/" <> non_existing_folder)
//   assert exists
//   let assert Ok(content) = simplifile.read(path)
//
//   assert content == "--- migration:up
//
// --- migration:down
//
// --- migration:end"
//
//   let assert Ok(_) = simplifile.delete("priv/" <> non_existing_folder)
// }
//
// pub fn create_new_migration_returns_error_if_name_too_long_test() {
//   let assert Ok(timestamp) = timestamp.parse_rfc3339("2024-11-17T18:36:41Z")
//   let config =
//     config.MigrationsConfig("cigogne", option.Some(migrations_folder), [])
//
//   let assert Error(err) =
//     fs.create_new_migration_file(config, timestamp, string.repeat("a", 256))
//   assert err == types.NameTooLongError(string.repeat("a", 256))
// }
