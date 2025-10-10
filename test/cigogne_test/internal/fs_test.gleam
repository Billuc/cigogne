import cigogne/internal/fs
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
