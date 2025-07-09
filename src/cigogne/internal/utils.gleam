import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
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

pub fn tempo_to_pog_timestamp(from: tempo.NaiveDateTime) -> timestamp.Timestamp {
  let #(#(year, month, day), #(hour, minutes, seconds)) =
    from |> naive_datetime.to_tuple

  let assert Ok(month) = calendar.month_from_int(month)

  let date = calendar.Date(year, month, day)
  let time = calendar.TimeOfDay(hour, minutes, seconds, 0)

  timestamp.from_calendar(date, time, calendar.utc_offset)
}

pub fn pog_to_tempo_timestamp(
  from: timestamp.Timestamp,
) -> Result(tempo.NaiveDateTime, Nil) {
  let #(date, time_of_day) = from |> timestamp.to_calendar(calendar.utc_offset)

  use date <- result.try(pog_to_tempo_date(date))
  use time <- result.try(pog_to_tempo_time(time_of_day))
  Ok(naive_datetime.new(date, time))
}

fn pog_to_tempo_date(from: calendar.Date) -> Result(tempo.Date, Nil) {
  date.new(from.year, from.month |> calendar.month_to_int(), from.day)
  |> result.replace_error(Nil)
}

fn pog_to_tempo_time(from: calendar.TimeOfDay) -> Result(tempo.Time, Nil) {
  time.new(from.hours, from.minutes, from.seconds) |> result.replace_error(Nil)
}

pub fn pog_timestamp_to_string(value: timestamp.Timestamp) -> String {
  let #(date, time_of_day) = value |> timestamp.to_calendar(calendar.utc_offset)

  [date.year, date.month |> calendar.month_to_int(), date.day]
  |> list.map(int.to_string)
  |> string.join("-")
  <> " "
  <> [time_of_day.hours, time_of_day.minutes, time_of_day.seconds]
  |> list.map(fn(v: Int) {
    case v {
      v if v < 10 -> "0" <> int.to_string(v)
      _ -> int.to_string(v)
    }
  })
  |> string.join(":")
}

pub fn tempo_epoch() -> tempo.NaiveDateTime {
  naive_datetime.literal("1970-01-01 00:00:00")
}

pub fn make_sha256(content: String) -> String {
  crypto.hash(crypto.Sha256, bit_array.from_string(content))
  |> bit_array.base16_encode()
}
