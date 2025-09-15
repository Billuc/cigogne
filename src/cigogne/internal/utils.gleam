import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/order
import gleam/result
import gleam/time/calendar
import gleam/time/timestamp

pub fn epoch() -> timestamp.Timestamp {
  let epoch_date = calendar.Date(1970, calendar.January, 1)
  let epoch_time = calendar.TimeOfDay(0, 0, 0, 0)
  timestamp.from_calendar(epoch_date, epoch_time, calendar.utc_offset)
}

pub fn make_sha256(content: String) -> String {
  crypto.hash(crypto.Sha256, bit_array.from_string(content))
  |> bit_array.base16_encode()
}

pub fn find_compare(
  list: List(a),
  element: a,
  compare_fn: fn(a, a) -> order.Order,
) -> Result(a, Nil) {
  list
  |> list.find(fn(el) { compare_fn(element, el) == order.Eq })
}

pub fn list_difference(
  from: List(a),
  minus: List(a),
  compare_fn: fn(a, a) -> order.Order,
) -> List(a) {
  let sorted_from = list.sort(from, compare_fn)
  let sorted_minus = list.sort(minus, compare_fn)

  loop_and_find_difference(sorted_from, sorted_minus, [], compare_fn)
}

fn loop_and_find_difference(
  from: List(a),
  minus: List(a),
  diff_acc: List(a),
  compare_fn: fn(a, a) -> order.Order,
) -> List(a) {
  case from, minus {
    [], _ -> diff_acc |> list.reverse()
    [first, ..rest], [] ->
      loop_and_find_difference(rest, [], [first, ..diff_acc], compare_fn)
    [first_from, ..rest_from], [first_minus, ..rest_minus] -> {
      case compare_fn(first_from, first_minus) {
        order.Eq ->
          loop_and_find_difference(rest_from, rest_minus, diff_acc, compare_fn)
        order.Gt ->
          loop_and_find_difference(from, rest_minus, diff_acc, compare_fn)
        order.Lt ->
          loop_and_find_difference(
            rest_from,
            minus,
            [first_from, ..diff_acc],
            compare_fn,
          )
      }
    }
  }
}

pub fn find_matches(
  elements: List(a),
  matches: List(a),
  compare_fn: fn(a, a) -> order.Order,
) -> List(#(a, Result(a, Nil))) {
  let sorted_elements = list.sort(elements, compare_fn)
  let sorted_matches = list.sort(matches, compare_fn)

  loop_and_find_matches(sorted_elements, sorted_matches, [], compare_fn)
}

fn loop_and_find_matches(
  elements: List(a),
  matches: List(a),
  acc: List(#(a, Result(a, Nil))),
  compare: fn(a, a) -> order.Order,
) {
  case elements, matches {
    [], _ -> list.reverse(acc)
    [first, ..rest], [] ->
      loop_and_find_matches(rest, [], [#(first, Error(Nil)), ..acc], compare)
    [first_el, ..rest_el], [first_match, ..rest_matches] -> {
      case compare(first_el, first_match) {
        order.Eq ->
          loop_and_find_matches(
            rest_el,
            rest_matches,
            [#(first_el, Ok(first_match)), ..acc],
            compare,
          )
        order.Gt -> loop_and_find_matches(elements, rest_matches, acc, compare)
        order.Lt ->
          loop_and_find_matches(
            rest_el,
            matches,
            [#(first_el, Error(Nil)), ..acc],
            compare,
          )
      }
    }
  }
}

pub fn try_or(
  result: Result(a, b),
  or: d,
  callback: fn(a) -> Result(c, d),
) -> Result(c, d) {
  case result {
    Ok(v) -> callback(v)
    Error(_) -> Error(or)
  }
}

pub fn get_results_or_errors(
  results: List(Result(a, e)),
) -> Result(List(a), List(e)) {
  do_get_results_or_errors(results, Ok([]))
}

fn do_get_results_or_errors(
  results: List(Result(a, e)),
  result_so_far: Result(List(a), List(e)),
) -> Result(List(a), List(e)) {
  case results, result_so_far {
    [], Error(errs) -> Error(errs |> list.reverse())
    [], Ok(vals) -> Ok(vals |> list.reverse())
    [Error(err), ..rest], Ok(_vals) ->
      do_get_results_or_errors(rest, Error([err]))
    [Error(err), ..rest], Error(errs) ->
      do_get_results_or_errors(rest, Error([err, ..errs]))
    [Ok(val), ..rest], Ok(vals) ->
      do_get_results_or_errors(rest, Ok([val, ..vals]))
    [Ok(_val), ..rest], Error(errs) ->
      do_get_results_or_errors(rest, Error(errs))
  }
}
