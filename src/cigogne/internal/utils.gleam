import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import pog

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
    pog.QueryTimeout -> "Query Timeout"
  }
}

pub fn describe_transaction_error(error: pog.TransactionError(_)) -> String {
  case error {
    pog.TransactionQueryError(suberror) -> describe_query_error(suberror)
    pog.TransactionRolledBack(message) ->
      "Transaction rolled back : " <> message
  }
}

pub fn describe_decode_error(error: decode.DecodeError) -> String {
  "Expecting : "
  <> error.expected
  <> ", Got : "
  <> error.found
  <> " [at "
  <> error.path |> string.join("/")
  <> "]"
}

pub fn epoch() -> timestamp.Timestamp {
  let epoch_date = calendar.Date(1970, calendar.January, 1)
  let epoch_time = calendar.TimeOfDay(0, 0, 0, 0)
  timestamp.from_calendar(epoch_date, epoch_time, calendar.utc_offset)
}

pub fn make_sha256(content: String) -> String {
  crypto.hash(crypto.Sha256, bit_array.from_string(content))
  |> bit_array.base16_encode()
}
