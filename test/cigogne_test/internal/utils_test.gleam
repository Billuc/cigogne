import cigogne/internal/utils
import gleam/int
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

pub fn find_compare_found_test() {
  let list = ["Alice", "Bob", "Charlie"]
  let element = "Carlos"
  let compare_fn = fn(a, b) {
    string.compare(string.slice(a, 0, 1), string.slice(b, 0, 1))
  }

  let assert Ok(found) = utils.find_compare(list, element, compare_fn)

  assert found == "Charlie"
}

pub fn find_compare_not_found_test() {
  let list = ["Alice", "Bob", "Charlie"]
  let element = "David"
  let compare_fn = fn(a, b) {
    string.compare(string.slice(a, 0, 1), string.slice(b, 0, 1))
  }

  let assert Error(Nil) = utils.find_compare(list, element, compare_fn)
}

pub fn list_difference_test() {
  let list1 = ["Alice", "Bob", "Charlie", "David"]
  let list2 = ["Bob", "David"]
  let compare_fn = string.compare

  let difference = utils.list_difference(list1, list2, compare_fn)

  assert difference == ["Alice", "Charlie"]
}

pub fn list_difference_sorts_list_test() {
  let list1 = ["Bob", "Charlie", "Alice", "David"]
  let list2 = ["David", "Bob"]
  let compare_fn = string.compare

  let difference = utils.list_difference(list1, list2, compare_fn)

  assert difference == ["Alice", "Charlie"]
}

pub fn find_matches_test() {
  let list = ["Alice", "Bob", "Charlie", "David"]
  let matches = ["Carlos", "Diana", "Eve"]
  let compare_fn = fn(a, b) {
    string.compare(string.slice(a, 0, 1), string.slice(b, 0, 1))
  }

  let found = utils.find_matches(list, matches, compare_fn)

  assert found
    == [
      #("Alice", Error(Nil)),
      #("Bob", Error(Nil)),
      #("Charlie", Ok("Carlos")),
      #("David", Ok("Diana")),
    ]
}

pub fn try_or_test() {
  let ok_result: Result(String, Int) = Ok("42")
  let err_result: Result(String, Int) = Error(69)

  assert utils.try_or(ok_result, Nil, int.parse) == Ok(42)
  assert utils.try_or(err_result, Nil, int.parse) == Error(Nil)
}

pub fn get_results_or_errors_test() {
  let results = [Ok(1), Error("err1"), Ok(2), Error("err2")]
  let ok_results = [Ok(1), Ok(2), Ok(3)]

  assert utils.get_results_or_errors(results) == Error(["err1", "err2"])
  assert utils.get_results_or_errors(ok_results) == Ok([1, 2, 3])
}
