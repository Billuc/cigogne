import cigogne/internal/utils
import gleam/erlang/application
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub type File {
  File(path: String, content: String)
}

pub type FSError {
  MissingFolderError(folder: String)
  MissingFileError(file: String)
  PermissionError(path: String)
  CompoundError(errors: List(FSError))
}

pub fn priv(application_name: String) -> Result(String, FSError) {
  application.priv_directory(application_name)
  |> result.replace_error(MissingFolderError(application_name <> "/priv"))
}

pub fn read_file(path: String) -> Result(File, FSError) {
  case simplifile.is_file(path) {
    Ok(False) -> Error(MissingFileError(path))
    Error(_) -> Error(PermissionError(path))
    Ok(True) -> {
      simplifile.read(path)
      |> result.replace_error(PermissionError(path))
      |> result.map(fn(content) { File(path:, content:) })
    }
  }
}

pub fn create_directory(path: String) -> Result(Nil, FSError) {
  simplifile.create_directory_all(path)
  |> result.replace_error(PermissionError(path))
}

pub fn write_file(file: File) -> Result(Nil, FSError) {
  case simplifile.is_file(file.path) {
    Error(_) -> Error(PermissionError(file.path))
    Ok(True) -> Ok(Nil)
    Ok(False) ->
      simplifile.create_file(file.path)
      |> result.replace_error(PermissionError(file.path))
  }
  |> result.try(fn(_) {
    simplifile.write(file.path, file.content)
    |> result.replace_error(PermissionError(file.path))
    |> result.replace(Nil)
  })
}

pub fn read_directory(path: String) -> Result(List(File), FSError) {
  case simplifile.is_directory(path) {
    Ok(False) -> Error(MissingFolderError(path))
    Error(_) -> Error(PermissionError(path))
    Ok(True) -> {
      use files <- result.try(
        simplifile.read_directory(path)
        |> result.replace_error(PermissionError(path)),
      )

      files |> list.map(fn(filename) { path <> "/" <> filename }) |> read_files
    }
  }
}

fn read_files(paths: List(String)) -> Result(List(File), FSError) {
  let results =
    {
      use acc, curr <- list.fold(paths, [])

      case simplifile.is_file(curr) {
        Error(_) -> [Error(PermissionError(curr)), ..acc]
        Ok(False) -> acc
        Ok(True) -> [read_file(curr), ..acc]
      }
    }
    |> list.reverse()

  utils.get_results_or_errors(results)
  |> result.map_error(CompoundError)
}

pub fn get_error_message(error: FSError) -> String {
  case error {
    CompoundError(errors:) ->
      "List of errors : [\n"
      <> errors |> list.map(get_error_message) |> string.join(",\n\t")
      <> "\n]"
    MissingFileError(file:) -> "Could not find file at path " <> file
    MissingFolderError(folder:) ->
      "Could not find folder at path " <> folder <> "/"
    PermissionError(path:) -> "Insufficient permission at path " <> path
  }
}
