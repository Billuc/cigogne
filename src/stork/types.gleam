import gleam/dynamic
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import pog

pub type MigrateError {
  EnvVarError(name: String)
  UrlError(url: String)
  FileError(path: String)
  PatternError(error: String)
  FileNameError(path: String)
  CompoundError(errors: List(MigrateError))
  ContentError(path: String, error: String)
  PGOTransactionError(error: pog.TransactionError)
  PGOQueryError(error: pog.QueryError)
  MigrationNotFoundError(number: Int)
  NoResultError
  SchemaQueryError(error: String)
}

pub type Migration {
  Migration(
    path: String,
    number: Int,
    name: String,
    queries_up: List(String),
    queries_down: List(String),
  )
}

pub fn print_migrate_error(error: MigrateError) -> Nil {
  case error {
    CompoundError(suberrors) -> {
      io.println_error("[")
      list.each(suberrors, print_migrate_error)
      io.println_error("]")
    }
    ContentError(path, message) ->
      io.println_error(
        "At [" <> path <> "]: Content wasn't right <" <> message <> ">",
      )
    EnvVarError(name) -> io.println_error("Couldn't find env var " <> name)
    FileError(path) ->
      io.println_error("Couldn't access file at path [" <> path <> "]")
    FileNameError(path) ->
      io.println_error(
        "Migration filenames should have the format <MigrationNumber>-<MigrationName>.sql ! Got: ["
        <> path
        <> "]",
      )
    MigrationNotFoundError(number) ->
      io.println_error(
        "Migration n°" <> int.to_string(number) <> " does not exist !",
      )
    NoResultError ->
      io.println_error(
        "Got no result from DB (can't get last applied migration)",
      )
    PGOQueryError(suberror) -> io.println_error(describe_query_error(suberror))
    PGOTransactionError(suberror) ->
      io.println_error(describe_transaction_error(suberror))
    PatternError(message) -> io.println_error(message)
    UrlError(url) -> io.println_error("Database URL badly formatted: " <> url)
    SchemaQueryError(err) ->
      io.println_error("Error while querying schema : " <> err)
  }
}

pub fn describe_query_error(error: pog.QueryError) -> String {
  case error {
    pog.ConnectionUnavailable -> "CONNECTION UNAVAILABLE"
    pog.ConstraintViolated(message, _constraint, _detail) -> message
    pog.PostgresqlError(_code, _name, message) ->
      "Postgresql error : " <> message
    pog.UnexpectedArgumentCount(expected, got) ->
      "Expected "
      <> int.to_string(expected)
      <> " arguments, got "
      <> int.to_string(got)
      <> " !"
    pog.UnexpectedArgumentType(expected, got) ->
      "Expected argument of type " <> expected <> ", got " <> got <> " !"
    pog.UnexpectedResultType(errs) ->
      "Unexpected result type ! \n"
      <> list.map(errs, describe_decode_error) |> string.join("\n")
  }
}

pub fn describe_transaction_error(error: pog.TransactionError) -> String {
  case error {
    pog.TransactionQueryError(suberror) -> describe_query_error(suberror)
    pog.TransactionRolledBack(message) ->
      "Transaction rolled back : " <> message
  }
}

pub fn describe_decode_error(error: dynamic.DecodeError) -> String {
  "Expecting : "
  <> error.expected
  <> ", Got : "
  <> error.found
  <> " [at "
  <> error.path |> string.join("/")
  <> "]"
}
