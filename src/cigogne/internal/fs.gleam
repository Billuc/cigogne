import cigogne/internal/utils
import cigogne/types
import gleam/bool
import gleam/list
import gleam/option
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

const max_name_length = 255

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

  use ts_and_name <- result.try(
    string.split(path, "/")
    |> list.last
    |> result.map(string.drop_end(_, 4))
    |> result.then(string.split_once(_, "-"))
    |> result.replace_error(types.FileNameError(path)),
  )

  use ts <- result.try(
    naive_datetime.parse(ts_and_name.0, "YYYYMMDDHHmmss")
    |> result.replace_error(types.DateParseError(ts_and_name.0)),
  )
  use name <- result.try(check_name(ts_and_name.1))

  #(ts, name) |> Ok
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

  use queries_up <- result.try(cut_migration_down.0 |> split_queries)
  use queries_down <- result.try(cut_end.0 |> split_queries)

  case queries_up, queries_down {
    [], _ -> Error("migration:up is empty !")
    _, [] -> Error("migration:down is empty !")
    up, down -> Ok(#(up, down))
  }
}

fn split_queries(queries: String) -> Result(List(String), String) {
  let graphemes = queries |> string.to_graphemes

  use queries <- result.try(
    analyse_sql_graphemes(graphemes, [], SimpleContext, []),
  )

  queries
  |> list.reverse
  |> list.map(string.trim)
  |> list.filter(fn(q) { !string.is_empty(q) })
  |> list.map(fn(q) { q <> ";" })
  |> Ok
}

type QueryContext {
  SimpleContext
  InStringLiteral
  InDollarQuoted(tag: String)
  InDollarTag(tag_so_far: List(String), parent_tag: option.Option(String))
}

fn analyse_sql_graphemes(
  sql_graphemes: List(String),
  previous_graphemes: List(String),
  context: QueryContext,
  queries: List(String),
) -> Result(List(String), String) {
  case sql_graphemes, context {
    [], SimpleContext -> queries |> add_if_not_empty(previous_graphemes) |> Ok
    [], _ -> Error("Migration badly formated: Unfinished literal")
    [";", ..rest], SimpleContext ->
      analyse_sql_graphemes(
        rest,
        [],
        SimpleContext,
        queries |> add_if_not_empty(previous_graphemes),
      )
    ["'", ..rest], SimpleContext ->
      analyse_sql_graphemes(
        rest,
        ["'", ..previous_graphemes],
        InStringLiteral,
        queries,
      )
    ["'", ..rest], InStringLiteral ->
      analyse_sql_graphemes(
        rest,
        ["'", ..previous_graphemes],
        SimpleContext,
        queries,
      )
    ["$", ..rest], SimpleContext ->
      analyse_sql_graphemes(
        rest,
        ["$", ..previous_graphemes],
        InDollarTag([], option.None),
        queries,
      )
    ["$", ..rest], InDollarTag(tag, option.None) ->
      analyse_sql_graphemes(
        rest,
        ["$", ..previous_graphemes],
        InDollarQuoted(tag |> list.reverse |> string.join("")),
        queries,
      )
    ["$", ..rest], InDollarTag(tag_graphemes, option.Some(tag)) ->
      analyse_sql_graphemes(
        rest,
        ["$", ..previous_graphemes],
        case tag_graphemes |> list.reverse |> string.join("") {
          a if a == tag -> SimpleContext
          _ -> InDollarQuoted(tag)
        },
        queries,
      )
    ["$", ..rest], InDollarQuoted(tag) ->
      analyse_sql_graphemes(
        rest,
        ["$", ..previous_graphemes],
        InDollarTag([], option.Some(tag)),
        queries,
      )
    [g, ..rest], InDollarTag([], parent) ->
      analyse_sql_graphemes(
        rest,
        [g, ..previous_graphemes],
        case g {
          "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ->
            case parent {
              option.None -> SimpleContext
              option.Some(tag) -> InDollarQuoted(tag)
            }
          _ -> InDollarTag([g], parent)
        },
        queries,
      )
    [g, ..rest], InDollarTag(tag_graphemes, parent) ->
      analyse_sql_graphemes(
        rest,
        [g, ..previous_graphemes],
        InDollarTag([g, ..tag_graphemes], parent),
        queries,
      )
    [g, ..rest], ctx ->
      analyse_sql_graphemes(rest, [g, ..previous_graphemes], ctx, queries)
  }
}

fn add_if_not_empty(
  string_list: List(String),
  graphemes_to_add: List(String),
) -> List(String) {
  case graphemes_to_add {
    [] -> string_list
    _ -> [graphemes_to_add |> list.reverse |> string.join(""), ..string_list]
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
  timestamp: tempo.NaiveDateTime,
  name: String,
) -> Result(String, types.MigrateError) {
  use name <- result.try(check_name(name))
  let file_path =
    migrations_folder
    <> "/"
    <> timestamp |> naive_datetime.format("YYYYMMDDHHmmss")
    <> "-"
    <> name
    <> ".sql"

  simplifile.create_directory_all(migrations_folder)
  |> result.then(fn(_) { simplifile.create_file(file_path) })
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
  |> result.map(fn(_) { file_path })
}

fn check_name(name: String) -> Result(String, types.MigrateError) {
  use <- bool.guard(
    string.length(name) > max_name_length,
    Error(types.NameTooLongError(name)),
  )
  Ok(name)
}
