import cigogne/internal/cli_lib
import gleam/dict
import gleam/float
import gleam/option
import gleam/result

pub fn bool_decoder_test() {
  let flag_decoder = cli_lib.bool

  assert flag_decoder.decode_fn(option.None) == Ok(False)
  assert flag_decoder.decode_fn(option.Some([])) == Ok(True)
  assert flag_decoder.decode_fn(option.Some(["true"])) == Ok(True)
  assert flag_decoder.decode_fn(option.Some(["yes"])) == Ok(True)
  assert flag_decoder.decode_fn(option.Some(["1"])) == Ok(True)
  assert flag_decoder.decode_fn(option.Some(["false"])) == Ok(False)
  assert flag_decoder.decode_fn(option.Some(["no"])) == Ok(False)
  assert flag_decoder.decode_fn(option.Some(["0"])) == Ok(False)
  assert flag_decoder.decode_fn(option.Some(["invalid"]))
    == Error("Expected a boolean, got 'invalid'")
}

pub fn int_decoder_test() {
  let flag_decoder = cli_lib.int

  assert flag_decoder.decode_fn(option.None) == Ok(option.None)
  assert flag_decoder.decode_fn(option.Some([])) == Error("No value provided")
  assert flag_decoder.decode_fn(option.Some(["42"])) == Ok(option.Some(42))
  assert flag_decoder.decode_fn(option.Some(["invalid"]))
    == Error("Expected an integer, got 'invalid'")
  assert flag_decoder.decode_fn(option.Some(["42", "43"]))
    == Ok(option.Some(42))
}

pub fn string_decoder_test() {
  let flag_decoder = cli_lib.string

  assert flag_decoder.decode_fn(option.None) == Ok(option.None)
  assert flag_decoder.decode_fn(option.Some([])) == Error("No value provided")
  assert flag_decoder.decode_fn(option.Some(["hello"]))
    == Ok(option.Some("hello"))
  assert flag_decoder.decode_fn(option.Some(["hello", "world"]))
    == Ok(option.Some("hello"))
}

pub fn required_flag_test() {
  let flag_decoder = cli_lib.required(cli_lib.int, 42)

  assert flag_decoder.decode_fn(option.None)
    == Error("This argument is required !")
  assert flag_decoder.decode_fn(option.Some([])) == Error("No value provided")
  assert flag_decoder.decode_fn(option.Some(["42"])) == Ok(42)
}

pub fn map_flag_test() {
  let flag_decoder =
    cli_lib.map(cli_lib.int, fn(v) { v |> option.map(fn(i) { i * 2 }) })

  assert flag_decoder.decode_fn(option.None) == Ok(option.None)
  assert flag_decoder.decode_fn(option.Some([])) == Error("No value provided")
  assert flag_decoder.decode_fn(option.Some(["42"])) == Ok(option.Some(84))
}

pub fn then_flag_test() {
  let flag_decoder =
    cli_lib.then(cli_lib.string, 0.0, fn(s) {
      s
      |> option.map(fn(v) {
        v |> float.parse |> result.replace_error("Not a float")
      })
      |> option.unwrap(Error("No value provided"))
    })

  assert flag_decoder.decode_fn(option.None) == Error("No value provided")
  assert flag_decoder.decode_fn(option.Some([])) == Error("No value provided")
  assert flag_decoder.decode_fn(option.Some(["3.14"])) == Ok(3.14)
  assert flag_decoder.decode_fn(option.Some(["invalid"]))
    == Error("Not a float")
}

pub fn action_decoder_test() {
  let action_decoder = cli_lib.options(26)

  assert action_decoder.decode(dict.new()) == #(26, [])
}

pub fn action_with_flags_test() {
  let action_decoder = {
    use flag_1 <- cli_lib.flag(
      "flag_1",
      [],
      "",
      "",
      cli_lib.required(cli_lib.int, 42),
    )
    use flag_2 <- cli_lib.flag("flag_2", [], "", "", cli_lib.bool)
    cli_lib.options(#(flag_1, flag_2))
  }

  assert action_decoder.decode(
      dict.new()
      |> dict.insert("flag_1", ["43"])
      |> dict.insert("flag_2", ["true"]),
    )
    == #(#(43, True), [])
  assert action_decoder.decode(
      dict.new()
      |> dict.insert("flag_1", ["invalid"])
      |> dict.insert("flag_2", ["true"]),
    )
    == #(#(42, True), [
      cli_lib.ParseError("Expected an integer, got 'invalid'", "flag_1"),
    ])
}

pub fn map_action_test() {
  let action_decoder =
    cli_lib.options(33) |> cli_lib.map_action(fn(v) { v * 3 })

  assert action_decoder.decode(dict.new()) == #(99, [])
}

pub fn then_action_test() {
  let action_decoder =
    {
      use a <- cli_lib.flag("a", [], "", "", cli_lib.int)
      cli_lib.options(a)
    }
    |> cli_lib.then_action(fn(a) {
      use b <- cli_lib.flag("b", [], "", "", cli_lib.int)
      case a, b {
        option.Some(a), option.Some(b) -> a + b
        option.Some(v), _ | _, option.Some(v) -> v
        _, _ -> 0
      }
      |> cli_lib.options
    })

  assert action_decoder.decode(
      dict.new() |> dict.insert("a", ["1"]) |> dict.insert("b", ["2"]),
    )
    == #(3, [])
}
