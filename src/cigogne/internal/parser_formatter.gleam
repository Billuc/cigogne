import cigogne/internal/fs
import cigogne/internal/utils
import cigogne/migration
import gleam/bool
import gleam/int
import gleam/list

// import gleam/option
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import splitter

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
  NotASQLFile(filepath: String)
  EmptyPath
}

pub fn parse(
  migration_file: fs.File,
) -> Result(migration.Migration, ParserError) {
  use <- bool.guard(
    !string.ends_with(migration_file.path, ".sql"),
    Error(NotASQLFile(migration_file.path)),
  )
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
  use timestamp <- result.try(
    parse_timestamp(timestamp_str)
    |> result.replace_error(WrongFormat(fullname)),
  )
  use name <- result.try(
    migration.check_name(name_str)
    |> result.map_error(MigrationError),
  )

  Ok(#(timestamp, name))
}

fn parse_timestamp(timestamp_str: String) -> Result(timestamp.Timestamp, Nil) {
  use <- bool.guard(string.length(timestamp_str) != 14, Error(Nil))

  let year = string.slice(timestamp_str, 0, 4) |> int.parse
  let month = string.slice(timestamp_str, 4, 2) |> int.parse
  let day = string.slice(timestamp_str, 6, 2) |> int.parse
  let hours = string.slice(timestamp_str, 8, 2) |> int.parse
  let minutes = string.slice(timestamp_str, 10, 2) |> int.parse
  let seconds = string.slice(timestamp_str, 12, 2) |> int.parse

  case year, month, day, hours, minutes, seconds {
    Ok(y), Ok(m), Ok(d), Ok(h), Ok(min), Ok(s) -> {
      calendar.month_from_int(m)
      |> result.map(fn(m) {
        timestamp.from_calendar(
          calendar.Date(y, m, d),
          calendar.TimeOfDay(h, min, s, 0),
          calendar.utc_offset,
        )
      })
    }
    _, _, _, _, _, _ -> Error(Nil)
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
  let splitter = splitter.new(["--", ";", "$", "'", "\n"])

  use queries <- result.try(do_split(splitter, queries, Simple, [], ""))

  queries
  |> list.reverse
  |> list.map(string.trim)
  |> list.filter(fn(q) { !string.is_empty(q) })
  |> list.map(fn(q) { q <> ";" })
  |> Ok
}

type QueryContext {
  Simple
  StringLiteral(parent_context: QueryContext)
  Comment(parent_context: QueryContext)
  DollarTag(parent_context: QueryContext)
  DollarQuoted(tag: String, parent_context: QueryContext)
}

fn do_split(
  splitter: splitter.Splitter,
  content: String,
  context: QueryContext,
  queries: List(String),
  current_query: String,
) -> Result(List(String), ParserError) {
  echo "Context: "
    <> string.inspect(context)
    <> " | Content: '"
    <> content
    <> "'"

  case splitter.split(splitter, content), context {
    #(before, ";", after), Simple ->
      do_split(
        splitter,
        after,
        Simple,
        [current_query <> before, ..queries],
        "",
      )
    #(before, "--", after), Simple | #(before, "--", after), DollarQuoted(_, _) ->
      do_split(
        splitter,
        after,
        Comment(context),
        queries,
        current_query <> before,
      )
    #(before, "'", after), Simple ->
      do_split(
        splitter,
        after,
        StringLiteral(context),
        queries,
        current_query <> before <> "'",
      )
    #(before, "$", after), Simple | #(before, "$", after), DollarQuoted(_, _) ->
      case after {
        "0" <> _
        | "1" <> _
        | "2" <> _
        | "3" <> _
        | "4" <> _
        | "5" <> _
        | "6" <> _
        | "7" <> _
        | "8" <> _
        | "9" <> _ ->
          do_split(
            splitter,
            after,
            context,
            queries,
            current_query <> before <> "$",
          )
        _ ->
          do_split(
            splitter,
            after,
            DollarTag(context),
            queries,
            current_query <> before <> "$",
          )
      }
    #(before, "'", after), StringLiteral(parent_ctx) ->
      do_split(
        splitter,
        after,
        parent_ctx,
        queries,
        current_query <> before <> "'",
      )
    #(_, "\n", after), Comment(parent_ctx) ->
      do_split(splitter, after, parent_ctx, queries, current_query)
    #(before, "$", after), DollarTag(DollarQuoted(tag, parent)) ->
      case before == tag {
        True ->
          do_split(
            splitter,
            after,
            parent,
            queries,
            current_query <> before <> "$",
          )
        False ->
          do_split(
            splitter,
            after,
            DollarQuoted(before, DollarQuoted(tag, parent)),
            queries,
            current_query <> before <> "$",
          )
      }
    #(before, "$", after), DollarTag(parent_ctx) ->
      do_split(
        splitter,
        after,
        DollarQuoted(before, parent_ctx),
        queries,
        current_query <> before <> "$",
      )
    #(before, "", _), Simple -> Ok([current_query <> before, ..queries])
    #(_, "", _), Comment(_) -> Ok(queries)
    #(_, "", _), StringLiteral(_) -> Error(UnfinishedLiteral("string literal"))
    #(_, "", _), DollarTag(_) -> Error(UnfinishedLiteral("dollar tag"))
    #(_, "", _), DollarQuoted(tag, _) ->
      Error(UnfinishedLiteral("dollar quoted text with tag '" <> tag <> "'"))
    #(_, _, after), Comment(_) ->
      do_split(splitter, after, context, queries, current_query)
    #(before, delim, after), ctx ->
      do_split(splitter, after, ctx, queries, current_query <> before <> delim)
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
      <> " isn't a valid migration name ! It should be YYYYMMDDHHmmss-<NAME>"
    NotASQLFile(filepath:) -> filepath <> " is not a .sql file"
  }
}
