import cigogne
import cigogne/internal/utils
import cigogne/types
import gleam/list
import gleeunit
import gleeunit/should
import simplifile
import tempo/naive_datetime

pub fn main() {
  gleeunit.main()
}

pub fn new_migration_test() {
  let test_folder = "/priv_test"

  simplifile.exist(test_folder)
}

pub fn test_tempo_format() {
  naive_datetime.literal("2024-12-14 08:57:12")
  |> naive_datetime.format(cigogne.timestamp_format)
  |> should.equal("20241214085712")
}

pub fn test_tempo_parse() {
  naive_datetime.parse("20241214085712", cigogne.timestamp_format)
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

pub fn create_zero_migration_test() {
  let migration = cigogne.create_zero_migration("test_zero", ["abc"], ["def"])

  migration
  |> should.equal(types.Migration(
    "",
    utils.tempo_epoch(),
    "test_zero",
    ["abc"],
    ["def"],
    "BEF57EC7F53A6D40BEB640A780A639C83BC29AC8A9816F1FC6C5C6DCD93C4721",
  ))

  migration
  |> cigogne.is_zero_migration()
  |> should.be_true
}
