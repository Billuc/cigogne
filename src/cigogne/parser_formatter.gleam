import cigogne/fs
import cigogne/internal/utils
import cigogne/migration
import gleam/bool
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp

const migration_up_guard = "--- migration:up"

const migration_down_guard = "--- migration:down"

const migration_end_guard = "--- migration:end"

pub type ParserError {
  MissingUpGuard(filepath: String)
  MissingDownGuard(filepath: String)
  MissingEndGuard(filepath: String)
  EmptyUpMigration(filepath: String)
  EmptyDownMigration(filepath: String)
  UnfinishedLiteral(context: String)
  WrongFormat(name: String)
  MigrationError(error: migration.MigrationError)
  EmptyPath
}

pub fn parse(
  migration_file: fs.File,
) -> Result(migration.Migration, ParserError) {
  use filename_without_ext <- result.try(
    migration_file.path
    |> string.split("/")
    |> list.last()
    |> result.replace_error(EmptyPath)
    |> result.map(string.drop_end(_, 4)),
  )

  use #(timestamp, name) <- result.try(parse_fullname(filename_without_ext))
  use #(ups, downs) <- result.try(parse_content(migration_file))

  Ok(migration.Migration(
    migration_file.path,
    timestamp,
    name,
    ups,
    downs,
    utils.make_sha256(migration_file.content),
  ))
}

fn parse_fullname(
  fullname: String,
) -> Result(#(timestamp.Timestamp, String), ParserError) {
  use #(timestamp_str, name_str) <- result.try(
    string.split_once(fullname, "-")
    |> result.replace_error(WrongFormat(fullname)),
  )
  use timestamp <- result.try(parse_timestamp(timestamp_str))
  use name <- result.try(
    migration.check_name(name_str)
    |> result.map_error(MigrationError),
  )

  Ok(#(timestamp, name))
}

fn parse_timestamp(
  timestamp_str: String,
) -> Result(timestamp.Timestamp, ParserError) {
  use <- bool.guard(
    string.length(timestamp_str) != 14,
    Error(WrongFormat(timestamp_str)),
  )

  let year = string.slice(timestamp_str, 0, 4) |> int.parse
  let month = string.slice(timestamp_str, 4, 2) |> int.parse
  let day = string.slice(timestamp_str, 6, 2) |> int.parse
  let hours = string.slice(timestamp_str, 8, 2) |> int.parse
  let minutes = string.slice(timestamp_str, 10, 2) |> int.parse
  let seconds = string.slice(timestamp_str, 12, 2) |> int.parse

  case year, month, day, hours, minutes, seconds {
    Ok(y), Ok(m), Ok(d), Ok(h), Ok(min), Ok(s) -> {
      calendar.month_from_int(m)
      |> result.replace_error(WrongFormat(timestamp_str))
      |> result.map(fn(m) {
        timestamp.from_calendar(
          calendar.Date(y, m, d),
          calendar.TimeOfDay(h, min, s, 0),
          calendar.utc_offset,
        )
      })
    }
    _, _, _, _, _, _ -> Error(WrongFormat(timestamp_str))
  }
}

fn parse_content(
  file: fs.File,
) -> Result(#(List(String), List(String)), ParserError) {
  use #(_, up_and_rest) <- result.try(
    file.content
    |> string.split_once(migration_up_guard)
    |> result.replace_error(MissingUpGuard(file.path)),
  )
  use #(up, down_and_rest) <- result.try(
    up_and_rest
    |> string.split_once(migration_down_guard)
    |> result.replace_error(MissingDownGuard(file.path)),
  )
  use #(down, _rest) <- result.try(
    down_and_rest
    |> string.split_once(migration_end_guard)
    |> result.replace_error(MissingEndGuard(file.path)),
  )

  use queries_up <- result.try(split_queries(up))
  use queries_down <- result.try(split_queries(down))

  case queries_up, queries_down {
    [], _ -> Error(EmptyUpMigration(file.path))
    _, [] -> Error(EmptyDownMigration(file.path))
    ups, downs -> Ok(#(ups, downs))
  }
}

fn split_queries(queries: String) -> Result(List(String), ParserError) {
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
) -> Result(List(String), ParserError) {
  case sql_graphemes, context {
    [], SimpleContext -> queries |> add_if_not_empty(previous_graphemes) |> Ok
    [], InStringLiteral -> Error(UnfinishedLiteral("string literal"))
    [], InDollarQuoted(tag:) ->
      Error(UnfinishedLiteral("dollar quoted text with tag '" <> tag <> "'"))
    [], InDollarTag(_, _) -> Error(UnfinishedLiteral("dollar tag"))
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

pub fn format(migration: migration.Migration) -> fs.File {
  let content =
    migration_up_guard
    <> "\n"
    <> migration.queries_up |> string.join("\n")
    <> "\n"
    <> migration_down_guard
    <> "\n"
    <> migration.queries_down |> string.join("\n")
    <> "\n"
    <> migration_end_guard

  fs.File(path: migration.path, content:)
}

pub fn get_error_message(error: ParserError) -> String {
  case error {
    EmptyDownMigration(filepath:) ->
      "In file " <> filepath <> ": Empty down migration"
    EmptyPath -> "Cannot parse migration from an empty path"
    EmptyUpMigration(filepath:) ->
      "In file " <> filepath <> ": Empty up migration"
    MissingDownGuard(filepath:) ->
      "In file "
      <> filepath
      <> ": Missing down guard ("
      <> migration_down_guard
      <> ")"
    MissingEndGuard(filepath:) ->
      "In file "
      <> filepath
      <> ": Missing up guard ("
      <> migration_up_guard
      <> ")"
    MissingUpGuard(filepath:) ->
      "In file "
      <> filepath
      <> ": Missing end guard ("
      <> migration_end_guard
      <> ")"
    MigrationError(error:) ->
      "Migration error: " <> migration.get_error_message(error)
    UnfinishedLiteral(context:) -> "Invalid migration: Unfinished " <> context
    WrongFormat(name:) ->
      name
      <> " isn't a valid migration name !\nIt should be YYYYMMDDHHmmss-<NAME>"
  }
}
