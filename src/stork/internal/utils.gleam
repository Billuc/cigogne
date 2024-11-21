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
