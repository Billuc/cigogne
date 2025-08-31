import cigogne/config
import cigogne/internal/migration_parser
import cigogne/internal/migrations_utils
import cigogne/internal/utils
import cigogne/types
import gleam/bool
import gleam/erlang/application
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/time/timestamp
import simplifile

const default_migration_folder = "migrations"

pub fn get_migrations(
  config: config.MigrationsConfig,
  application_name: String,
) -> Result(List(types.Migration), types.MigrateError) {
  use migrations_folder <- result.try(create_migration_folder(
    application_name,
    config.migration_folder |> option.unwrap(default_migration_folder),
  ))

  use files <- result.try(
    simplifile.read_directory(migrations_folder)
    |> result.replace_error(types.FileError(migrations_folder <> "/*.sql")),
  )
  read_migration_files(
    files |> list.map(fn(filename) { migrations_folder <> "/" <> filename }),
  )
}

fn read_migration_files(
  files: List(String),
) -> Result(List(types.Migration), types.MigrateError) {
  let results = {
    use migs, file <- list.fold(files, [])
    use <- bool.guard(!string.ends_with(file, ".sql"), migs)
    case simplifile.is_file(file) {
      Error(_) | Ok(False) -> migs
      Ok(True) -> {
        [read_migration_file(file), ..migs]
      }
    }
  }

  case results |> result.partition {
    #(migs, []) -> Ok(migs)
    #(_, errs) -> Error(types.CompoundError(errs))
  }
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

pub fn create_new_migration_file(
  config: config.MigrationsConfig,
  application_name: String,
  timestamp: timestamp.Timestamp,
  name: String,
) -> Result(String, types.MigrateError) {
  use name <- result.try(migrations_utils.check_name(name))
  use migrations_folder <- result.try(create_migration_folder(
    application_name,
    config.migration_folder |> option.unwrap(default_migration_folder),
  ))

  let file_path =
    migrations_folder
    <> "/"
    <> migrations_utils.to_migration_filename(timestamp, name)

  simplifile.create_file(file_path)
  |> result.try(fn(_) {
    file_path
    |> simplifile.write(
      migration_parser.migration_up_guard
      <> "\n\n"
      <> migration_parser.migration_down_guard
      <> "\n\n"
      <> migration_parser.migration_end_guard,
    )
  })
  |> result.replace_error(types.FileError(file_path))
  |> result.map(fn(_) { file_path })
}

fn create_migration_folder(
  application_name: String,
  migrations_folder: String,
) -> Result(String, types.MigrateError) {
  let folder_path =
    application.priv_directory(application_name) |> result.unwrap("priv")
    <> "/"
    <> migrations_folder

  simplifile.create_directory_all(folder_path)
  |> result.replace_error(types.CreateFolderError(migrations_folder))
  |> result.replace(folder_path)
}
