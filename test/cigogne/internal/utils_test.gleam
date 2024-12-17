import cigogne/internal/utils
import gleeunit/should
import tempo/naive_datetime

pub fn test_tempo_epoch() {
  utils.tempo_epoch()
  |> naive_datetime.to_tuple
  |> should.equal(#(#(1970, 1, 1), #(0, 0, 0)))
}
