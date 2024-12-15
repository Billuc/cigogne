import gleam/list
import gleeunit
import gleeunit/should
import tempo/naive_datetime

pub fn main() {
  gleeunit.main()
}

// gleeunit test functions end in `_test`
pub fn hello_world_test() {
  1
  |> should.equal(1)
}

pub fn test_tempo_format() {
  naive_datetime.literal("2024-12-14 08:57:12")
  |> naive_datetime.format("YYYYMMDDhhmmss")
  |> should.equal("20241214085712")
}

pub fn test_tempo_parse() {
  naive_datetime.parse("20241214085712", "YYYYMMDDhhmmss")
  |> should.be_ok
  |> naive_datetime.to_tuple
  |> should.equal(#(#(2024, 12, 14), #(08, 57, 12)))
}

pub fn test_tempo_duration() {
  let time1 = naive_datetime.literal("2024-11-14 08:08:08")
  let time2 = naive_datetime.literal("2024-11-13 08:08:08")
  let time3 = naive_datetime.literal("2024-11-13 15:08:08")
  let times = [time1, time2, time3]

  list.sort(times, naive_datetime.compare)
  |> should.equal([time2, time3, time1])
}
