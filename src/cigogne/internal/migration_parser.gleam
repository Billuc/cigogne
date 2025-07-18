import cigogne/internal/migrations_utils
import cigogne/types
import gleam/bool
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import tempo
import tempo/naive_datetime

pub const migration_up_guard = "--- migration:up"

pub const migration_down_guard = "--- migration:down"

pub const migration_end_guard = "--- migration:end"

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
    |> result.try(string.split_once(_, "-"))
    |> result.replace_error(types.FileNameError(path)),
  )

  use ts <- result.try(
    naive_datetime.parse(ts_and_name.0, migrations_utils.timestamp_format)
    |> result.replace_error(types.DateParseError(ts_and_name.0)),
  )
  use name <- result.try(migrations_utils.check_name(ts_and_name.1))

  #(ts, name) |> Ok
}

pub fn parse_migration_file(
  content: String,
) -> Result(#(List(String), List(String)), String) {
  case string.split_once(content, migration_up_guard) {
    Error(_) ->
      Error("File badly formatted: '" <> migration_up_guard <> "' not found !")
    Ok(#(_, up_and_rest)) -> {
      case string.split_once(up_and_rest, migration_down_guard) {
        Error(_) ->
          Error(
            "File badly formatted: '" <> migration_down_guard <> "' not found !",
          )
        Ok(#(up, down_and_rest)) -> {
          case string.split_once(down_and_rest, migration_end_guard) {
            Error(_) ->
              Error(
                "File badly formatted: '"
                <> migration_end_guard
                <> "' not found !",
              )
            Ok(#(down, _rest)) -> {
              use queries_up <- result.try(split_queries(up))
              use queries_down <- result.try(split_queries(down))

              case queries_up, queries_down {
                [], _ -> Error("migration:up is empty !")
                _, [] -> Error("migration:down is empty !")
                ups, downs -> Ok(#(ups, downs))
              }
            }
          }
        }
      }
    }
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
