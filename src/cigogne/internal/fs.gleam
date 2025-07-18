import cigogne/internal/migration_parser
import cigogne/internal/migrations_utils
import cigogne/internal/utils
import cigogne/types
import gleam/list
import gleam/result
import globlin
import globlin_fs
import simplifile
import tempo

pub fn get_migrations(
  migrations_folder: String,
  file_pattern: String,
) -> Result(List(types.Migration), types.MigrateError) {
  use _ <- result.try(create_migration_folder(migrations_folder))

  let migration_file_pattern = migrations_folder <> "/" <> file_pattern
  globlin.new_pattern(migration_file_pattern)
  |> result.replace_error(types.PatternError(
    "Something is wrong with the search pattern !",
  ))
  |> result.try(fn(pattern) {
    globlin_fs.glob_from(pattern, migrations_folder, globlin_fs.RegularFiles)
    |> result.replace_error(types.FileError(migration_file_pattern))
  })
  |> result.try(fn(files) {
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

pub fn read_migration_file(
  path: String,
) -> Result(types.Migration, types.MigrateError) {
  use ts_and_name <- result.try(migration_parser.parse_file_name(path))
  use content <- result.try(
    simplifile.read(path) |> result.replace_error(types.FileError(path)),
  )

  let sha256 = utils.make_sha256(content)

  case migration_parser.parse_migration_file(content) {
    Error(error) -> Error(types.ContentError(path, error))
    Ok(#(queries_up, queries_down)) ->
      Ok(types.Migration(
        path:,
        queries_up:,
        queries_down:,
        timestamp: ts_and_name.0,
        name: ts_and_name.1,
        sha256:,
      ))
  }
}

pub fn read_schema_file(
  schema_file_path: String,
) -> Result(String, types.MigrateError) {
  simplifile.read(schema_file_path)
  |> result.replace_error(types.FileError(schema_file_path))
}

pub fn write_schema_file(
  schema_file_path: String,
  content: String,
) -> Result(Nil, types.MigrateError) {
  simplifile.write(schema_file_path, content)
  |> result.replace_error(types.FileError(schema_file_path))
}

pub fn create_new_migration_file(
  migrations_folder: String,
  timestamp: tempo.NaiveDateTime,
  name: String,
) -> Result(String, types.MigrateError) {
  use name <- result.try(migrations_utils.check_name(name))
  let file_path =
    migrations_folder
    <> "/"
    <> migrations_utils.to_migration_filename(timestamp, name)

  create_migration_folder(migrations_folder)
  |> result.try(fn(_) {
    simplifile.create_file(file_path)
    |> result.replace_error(types.FileError(file_path))
  })
  |> result.try(fn(_) {
    file_path
    |> simplifile.write(
      migration_parser.migration_up_guard
      <> "\n\n"
      <> migration_parser.migration_down_guard
      <> "\n\n"
      <> migration_parser.migration_end_guard,
    )
    |> result.replace_error(types.FileError(file_path))
  })
  |> result.map(fn(_) { file_path })
}

fn create_migration_folder(
  migrations_folder: String,
) -> Result(Nil, types.MigrateError) {
  simplifile.create_directory_all(migrations_folder)
  |> result.replace_error(types.CreateFolderError(migrations_folder))
}
