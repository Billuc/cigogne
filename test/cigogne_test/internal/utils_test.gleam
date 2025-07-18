import cigogne/internal/utils
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import gleeunit/should
import tempo/naive_datetime

pub fn tempo_epoch_test() {
  utils.tempo_epoch()
  |> naive_datetime.to_tuple
  |> should.equal(#(#(1970, 1, 1), #(0, 0, 0)))
}

pub fn tempo_to_pog_test() {
  naive_datetime.literal("2004-10-15T04:25:33")
  |> utils.tempo_to_pog_timestamp
  |> should.equal(timestamp.from_calendar(
    calendar.Date(2004, calendar.October, 15),
    calendar.TimeOfDay(04, 25, 33, 0),
    calendar.utc_offset,
  ))
}

pub fn pog_to_tempo_test() {
  timestamp.from_calendar(
    calendar.Date(2410, calendar.December, 24),
    calendar.TimeOfDay(16, 42, 0, 0),
    calendar.utc_offset,
  )
  |> utils.pog_to_tempo_timestamp
  |> should.be_ok
  |> should.equal(naive_datetime.literal("2410-12-24T16:42:00"))
}

pub fn pog_to_string_test() {
  timestamp.from_calendar(
    calendar.Date(2410, calendar.December, 24),
    calendar.TimeOfDay(16, 42, 0, 0),
    calendar.utc_offset,
  )
  |> utils.pog_timestamp_to_string
  |> should.equal("2410-12-24 16:42:00")
}

pub fn make_sha256_test() {
  "Hello world !"
  |> utils.make_sha256()
  |> string.lowercase()
  |> should.equal(
    "2f951d3adf29ab254d734286755e2131c397b6fc1894e6ffe5b236ea5e099ecf",
  )
}
