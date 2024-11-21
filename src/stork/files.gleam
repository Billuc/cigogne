import gleam/int
import gleam/list
import gleam/result
import gleam/string
import globlin
import globlin_fs
import simplifile
import stork/types

const schema_file_path = "./sql.schema"

const migration_up_guard = "--- migration:up"

const migration_down_guard = "--- migration:down"

const migration_end_guard = "--- migration:end"

pub fn get_migrations() -> Result(List(types.Migration), types.MigrateError) {
  globlin.new_pattern("**/migrations/*.sql")
  |> result.replace_error(types.PatternError(
    "Something is wrong with the search pattern !",
  ))
  |> result.then(fn(pattern) {
    globlin_fs.glob(pattern, globlin_fs.RegularFiles)
    |> result.replace_error(types.FileError(
      "There was a problem accessing some files !",
    ))
  })
  |> result.then(fn(files) {
    let res =
      files
      |> list.map(read_migration_file)
      |> result.partition

    case res {
      #(res_ok, []) -> Ok(res_ok)
      #(_, errs) -> Error(types.CompoundError(errs))
    }
  })
}

fn read_migration_file(
  path: String,
) -> Result(types.Migration, types.MigrateError) {
  use num_and_name <- result_guard(
    parse_file_name(path),
    Error(types.FileNameError(path)),
  )
  use content <- result_guard(
    simplifile.read(path),
    Error(types.FileError(path)),
  )

  case parse_migration_file(content) {
    Error(error) -> Error(types.ContentError(path, error))
    Ok(#(up, down)) ->
      Ok(types.Migration(path, num_and_name.0, num_and_name.1, up, down))
  }
}

pub fn parse_file_name(path: String) -> Result(#(Int, String), Nil) {
  let filename = string.split(path, "/") |> list.last()
  use file <- result_guard(filename, Error(Nil))

  let splitted_filename = file |> string.drop_end(4) |> string.split_once("-")
  use num_and_name <- result_guard(splitted_filename, Error(Nil))

  use num <- result_guard(int.parse(num_and_name.0), Error(Nil))
  Ok(#(num, num_and_name.1))
}

pub fn parse_migration_file(
  content: String,
) -> Result(#(List(String), List(String)), String) {
  use cut_migration_up <- result_guard(
    string.split_once(content, migration_up_guard),
    Error("File badly formatted: '" <> migration_up_guard <> "' not found !"),
  )
  use cut_migration_down <- result_guard(
    string.split_once(cut_migration_up.1, migration_down_guard),
    Error("File badly formatted: '" <> migration_down_guard <> "' not found !"),
  )
  use cut_end <- result_guard(
    string.split_once(cut_migration_down.1, migration_end_guard),
    Error("File badly formatted: '" <> migration_end_guard <> "' not found !"),
  )

  let queries_up = cut_migration_down.0 |> split_queries
  let queries_down = cut_end.0 |> split_queries

  case queries_up, queries_down {
    [], _ -> Error("migration:up is empty !")
    _, [] -> Error("migration:down is empty !")
    up, down -> Ok(#(up, down))
  }
}

fn split_queries(queries: String) -> List(String) {
  queries
  |> string.split(";")
  |> list.map(string.trim)
  |> list.filter(fn(q) { !string.is_empty(q) })
  |> list.map(fn(q) { q <> ";" })
}

fn result_guard(result: Result(a, b), otherwise: c, callback: fn(a) -> c) -> c {
  case result {
    Error(_) -> otherwise
    Ok(v) -> callback(v)
  }
}

pub fn write_schema_file(content: String) -> Result(Nil, types.MigrateError) {
  simplifile.write(schema_file_path, content)
  |> result.replace_error(types.FileError(schema_file_path))
}
