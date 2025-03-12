import cigogne/no_down/types
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import globlin
import globlin_fs
import simplifile

const migrations_folder = "priv/migrations"

const migration_file_pattern = migrations_folder <> "/*.sql"

const schema_file_path = "./sql.schema"

pub fn get_migrations() -> Result(List(types.Migration), types.MigrateError) {
  globlin.new_pattern(migration_file_pattern)
  |> result.replace_error(types.PatternError(
    "Something is wrong with the search pattern !",
  ))
  |> result.then(fn(pattern) {
    globlin_fs.glob_from(pattern, migrations_folder, globlin_fs.RegularFiles)
    |> result.replace_error(types.FileError(migration_file_pattern))
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
  |> result.then(check_migrations)
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
    Ok(queries) ->
      Ok(types.Migration(path, num_and_name.0, num_and_name.1, queries))
  }
}

pub fn parse_file_name(
  path: String,
) -> Result(#(Int, String), types.MigrateError) {
  use <- bool.guard(
    !string.ends_with(path, ".sql"),
    Error(types.FileNameError(path)),
  )

  let index_and_name =
    string.split(path, "/")
    |> list.last
    |> result.map(string.drop_end(_, 4))
    |> result.then(string.split_once(_, "-"))

  let index =
    index_and_name
    |> result.then(fn(v) {
      int.parse(v.0)
      |> result.replace_error(Nil)
    })

  case index, index_and_name {
    Ok(n), Ok(#(_, name)) -> Ok(#(n, name))
    _, _ -> Error(types.FileNameError(path))
  }
}

pub fn parse_migration_file(content: String) -> Result(List(String), String) {
  let queries = content |> split_queries
  Ok(queries)
}

fn split_queries(queries: String) -> List(String) {
  queries
  |> string.split(";")
  |> list.map(string.trim)
  |> list.filter(fn(q) { !string.is_empty(q) })
  |> list.map(fn(q) { q <> ";" })
}

fn check_migrations(
  migrations: List(types.Migration),
) -> Result(List(types.Migration), types.MigrateError) {
  let conflicts =
    list.group(migrations, fn(mig) { mig.index })
    |> dict.values
    |> list.filter(fn(migs_by_index) { list.length(migs_by_index) > 1 })

  case conflicts {
    [] -> Ok(migrations)
    [conflict] -> conflict_to_error(conflict) |> Error
    _ ->
      conflicts |> list.map(conflict_to_error) |> types.CompoundError |> Error
  }
}

fn conflict_to_error(conflict: List(types.Migration)) -> types.MigrateError {
  case conflict {
    [] -> types.ConflictingMigrationsError(-1, [])
    [mig_a, ..] ->
      types.ConflictingMigrationsError(
        mig_a.index,
        conflict |> list.map(fn(mig) { mig.name }),
      )
  }
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
  index: Int,
  name: String,
) -> Result(String, types.MigrateError) {
  let file_path =
    migrations_folder <> "/" <> index |> int.to_string <> "-" <> name <> ".sql"

  create_migration_folder()
  |> result.then(fn(_) {
    simplifile.create_file(file_path)
    |> result.replace_error(types.FileError(file_path))
    |> result.map(fn(_) { file_path })
  })
}

pub fn create_migration_folder() -> Result(String, types.MigrateError) {
  simplifile.create_directory_all(migrations_folder)
  |> result.replace_error(types.FileError(migrations_folder))
  |> result.replace(migrations_folder)
}
