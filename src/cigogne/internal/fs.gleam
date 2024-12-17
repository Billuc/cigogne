import cigogne/internal/utils
import cigogne/types
import gleam/bool
import gleam/list
import gleam/result
import gleam/string
import globlin
import globlin_fs
import simplifile
import tempo
import tempo/naive_datetime

const migrations_folder = "priv/migrations"

const migration_file_pattern = migrations_folder <> "/*.sql"

const schema_file_path = "./sql.schema"

const migration_up_guard = "--- migration:up"

const migration_down_guard = "--- migration:down"

const migration_end_guard = "--- migration:end"

pub fn get_migrations() -> Result(List(types.Migration), types.MigrateError) {
  globlin.new_pattern(migration_file_pattern)
  |> result.replace_error(types.PatternError(
    "Something is wrong with the search pattern !",
  ))
  |> result.then(fn(pattern) {
    globlin_fs.glob_from(pattern, migrations_folder, globlin_fs.RegularFiles)
    |> result.replace_error(types.FileError(
      "There was a problem accessing some files/folders !",
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
  use num_and_name <- result.try(parse_file_name(path))
  use content <- result.try(
    simplifile.read(path) |> result.replace_error(types.FileError(path)),
  )

  case parse_migration_file(content) {
    Error(error) -> Error(types.ContentError(path, error))
    Ok(#(up, down)) ->
      Ok(types.Migration(path, num_and_name.0, num_and_name.1, up, down))
  }
}

pub fn parse_file_name(
  path: String,
) -> Result(#(tempo.NaiveDateTime, String), types.MigrateError) {
  use <- bool.guard(
    !string.ends_with(path, ".sql"),
    Error(types.FileNameError(path)),
  )

  let ts_and_name =
    string.split(path, "/")
    |> list.last
    |> result.map(string.drop_end(_, 4))
    |> result.then(string.split_once(_, "-"))

  let ts =
    ts_and_name
    |> result.then(fn(v) {
      naive_datetime.parse(v.0, "YYYYMMDDHHmmss")
      |> result.replace_error(Nil)
    })

  case ts, ts_and_name {
    Ok(n), Ok(#(_, name)) -> Ok(#(n, name))
    _, _ -> Error(types.FileNameError(path))
  }
}

pub fn parse_migration_file(
  content: String,
) -> Result(#(List(String), List(String)), String) {
  use cut_migration_up <- utils.result_guard(
    string.split_once(content, migration_up_guard),
    Error("File badly formatted: '" <> migration_up_guard <> "' not found !"),
  )
  use cut_migration_down <- utils.result_guard(
    string.split_once(cut_migration_up.1, migration_down_guard),
    Error("File badly formatted: '" <> migration_down_guard <> "' not found !"),
  )
  use cut_end <- utils.result_guard(
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

pub fn read_schema_file() -> Result(String, types.MigrateError) {
  simplifile.read(schema_file_path)
  |> result.replace_error(types.FileError(schema_file_path))
}

pub fn write_schema_file(content: String) -> Result(Nil, types.MigrateError) {
  simplifile.write(schema_file_path, content)
  |> result.replace_error(types.FileError(schema_file_path))
}

pub fn create_new_migration_file(
  timestamp: tempo.NaiveDateTime,
  name: String,
) -> Result(Nil, types.MigrateError) {
  let file_path =
    migrations_folder
    <> "/"
    <> timestamp |> naive_datetime.format("YYYYMMDDHHmmss")
    <> "-"
    <> name
    <> ".sql"

  simplifile.create_file(file_path)
  |> result.replace_error(types.FileError(file_path))
  |> result.then(fn(_) {
    file_path
    |> simplifile.write(
      migration_up_guard
      <> "\n\n"
      <> migration_down_guard
      <> "\n\n"
      <> migration_end_guard,
    )
    |> result.replace_error(types.FileError(file_path))
  })
}
