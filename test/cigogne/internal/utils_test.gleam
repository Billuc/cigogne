import cigogne/internal/utils
import gleeunit/should
import pog
import tempo/naive_datetime

pub fn tempo_epoch_test() {
  utils.tempo_epoch()
  |> naive_datetime.to_tuple
  |> should.equal(#(#(1970, 1, 1), #(0, 0, 0)))
}

pub fn tempo_to_pog_test() {
  naive_datetime.literal("2004-10-15T04:25:33")
  |> utils.tempo_to_pog_timestamp
  |> should.equal(pog.Timestamp(pog.Date(2004, 10, 15), pog.Time(04, 25, 33, 0)))
}

pub fn pog_to_tempo_test() {
  pog.Timestamp(pog.Date(2410, 12, 24), pog.Time(16, 42, 0, 0))
  |> utils.pog_to_tempo_timestamp
  |> should.be_ok
  |> should.equal(naive_datetime.literal("2410-12-24T16:42:00"))
}

pub fn pog_to_string_test() {
  pog.Timestamp(pog.Date(2410, 12, 24), pog.Time(16, 42, 0, 0))
  |> utils.pog_timestamp_to_string
  |> should.equal("2410-12-24 16:42:00")
}
