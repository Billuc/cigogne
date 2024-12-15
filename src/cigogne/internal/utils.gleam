import gleam/dynamic
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import pog
import tempo
import tempo/date
import tempo/naive_datetime
import tempo/time

pub fn result_guard(
  result: Result(a, b),
  otherwise: c,
  callback: fn(a) -> c,
) -> c {
  case result {
    Error(_) -> otherwise
    Ok(v) -> callback(v)
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

pub fn tempo_to_pog_timestamp(from: tempo.NaiveDateTime) -> pog.Timestamp {
  let as_tuple = from |> naive_datetime.to_tuple

  pog.Timestamp(
    pog.Date(as_tuple.0.0, as_tuple.0.1, as_tuple.0.2),
    pog.Time(as_tuple.1.0, as_tuple.1.1, as_tuple.1.2, 0),
  )
}

pub fn pog_to_tempo_timestamp(
  from: pog.Timestamp,
) -> Result(tempo.NaiveDateTime, Nil) {
  use date <- result.try(pog_to_tempo_date(from.date))
  use time <- result.try(pog_to_tempo_time(from.time))
  Ok(naive_datetime.new(date, time))
}

fn pog_to_tempo_date(from: pog.Date) -> Result(tempo.Date, Nil) {
  date.new(from.year, from.month, from.day) |> result.replace_error(Nil)
}

fn pog_to_tempo_time(from: pog.Time) -> Result(tempo.Time, Nil) {
  time.new(from.hours, from.minutes, from.seconds) |> result.replace_error(Nil)
}

pub fn pog_timestamp_to_string(value: pog.Timestamp) -> String {
  [value.date.year, value.date.month, value.date.day]
  |> list.map(int.to_string)
  |> string.join("-")
  <> " "
  <> [value.time.hours, value.time.minutes, value.time.seconds]
  |> list.map(int.to_string)
  |> string.join(":")
}

pub fn tempo_epoch() -> tempo.NaiveDateTime {
  naive_datetime.literal("1970-01-01 00:00:00")
}
