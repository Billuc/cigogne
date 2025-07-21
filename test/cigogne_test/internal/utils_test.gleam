import cigogne/internal/utils
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import gleeunit/should

pub fn epoch_test() {
  let #(date, time) =
    utils.epoch()
    |> timestamp.to_calendar(calendar.utc_offset)

  assert date == calendar.Date(1970, calendar.January, 1)
  assert time == calendar.TimeOfDay(0, 0, 0, 0)
}

pub fn make_sha256_test() {
  "Hello world !"
  |> utils.make_sha256()
  |> string.lowercase()
  |> should.equal(
    "2f951d3adf29ab254d734286755e2131c397b6fc1894e6ffe5b236ea5e099ecf",
  )
}
