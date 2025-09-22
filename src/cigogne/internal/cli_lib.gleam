import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string

const default_bool = False

const default_option = option.None

pub type Command(cmd_data) {
  Command(name: String, description: String, actions: List(Action(cmd_data)))
}

pub type Action(data) {
  Action(action_path: List(String), help: String, decoder: ActionDecoder(data))
}

pub type ActionDecoder(data) {
  ActionDecoder(
    default_value: data,
    flag_defs: List(Flag),
    decode: fn(dict.Dict(String, List(String))) -> #(data, List(ParseError)),
  )
}

pub type Flag {
  Flag(name: String, aliases: List(String), description: String, type_: String)
}

pub type FlagDecoder(a) {
  FlagDecoder(
    default_value: a,
    decode_fn: fn(option.Option(List(String))) -> Result(a, String),
  )
}

pub type ParseError {
  ParseError(message: String, argument: String)
}

pub fn command(name: String) -> Command(a) {
  Command(name, "", [])
}

pub fn with_description(command: Command(a), description: String) -> Command(a) {
  Command(..command, description:)
}

pub fn add_action(command: Command(a), action: Action(a)) -> Command(a) {
  Command(..command, actions: [action, ..command.actions])
}

pub fn create_action(
  action_path: List(String),
  help: String,
  decoder: ActionDecoder(a),
) -> Action(a) {
  Action(action_path, help, decoder)
}

pub fn with_help(action: Action(a), help: String) -> Action(a) {
  Action(..action, help:)
}

pub fn options(data: data) -> ActionDecoder(data) {
  ActionDecoder(data, [], fn(_) { #(data, []) })
}

pub fn then_action(
  decoder: ActionDecoder(a),
  then_fn: fn(a) -> ActionDecoder(b),
) -> ActionDecoder(b) {
  let decoder2 = then_fn(decoder.default_value)
  ActionDecoder(
    decoder2.default_value,
    list.append(decoder.flag_defs, decoder2.flag_defs),
    fn(v) {
      let #(res1, err1) = decoder.decode(v)
      let #(res2, err2) = then_fn(res1).decode(v)
      #(res2, list.append(err1, err2))
    },
  )
}

pub fn map_action(
  decoder: ActionDecoder(a),
  map_fn: fn(a) -> b,
) -> ActionDecoder(b) {
  ActionDecoder(map_fn(decoder.default_value), decoder.flag_defs, fn(v) {
    let #(res, err) = decoder.decode(v)
    #(map_fn(res), err)
  })
}

pub fn flag(
  name: String,
  aliases: List(String),
  value_type: String,
  description: String,
  decoder: FlagDecoder(a),
  then: fn(a) -> ActionDecoder(b),
) -> ActionDecoder(b) {
  let default_value = decoder.default_value
  let action_decoder = then(default_value)

  let decode_fn = fn(args: dict.Dict(String, List(String))) {
    let #(arg_name, value) =
      [name, ..aliases]
      |> get_argument(args)
      |> option.map(fn(opt) { #(opt.0, option.Some(opt.1)) })
      |> option.unwrap(#(name, option.None))

    let #(value, errs) =
      decoder.decode_fn(value)
      |> result.map_error(fn(err) { [ParseError(err, arg_name)] })
      |> result_to_tuple(default_value)

    let #(value, other_errs) = then(value).decode(args)
    #(value, list.append(errs, other_errs))
  }
  let flag = Flag(name, aliases, description, value_type)

  ActionDecoder(
    action_decoder.default_value,
    [flag, ..action_decoder.flag_defs],
    decode_fn,
  )
}

fn get_argument(
  names: List(String),
  args: dict.Dict(String, List(String)),
) -> option.Option(#(String, List(String))) {
  case names {
    [] -> option.None
    [name, ..rest] ->
      case dict.get(args, name) {
        Error(_) -> get_argument(rest, args)
        Ok(arg_value) -> option.Some(#(name, arg_value))
      }
  }
}

fn result_to_tuple(value: Result(a, List(b)), default_value: a) -> #(a, List(b)) {
  case value {
    Ok(v) -> #(v, [])
    Error(errs) -> #(default_value, errs)
  }
}

fn tuple_to_result(value: #(a, List(b))) -> Result(a, List(b)) {
  case value.1 {
    [] -> Ok(value.0)
    _ as errs -> Error(errs)
  }
}

pub const bool = FlagDecoder(default_bool, decode_bool)

pub const int = FlagDecoder(default_option, decode_int)

pub const string = FlagDecoder(default_option, decode_string)

fn decode_bool(values: option.Option(List(String))) -> Result(Bool, String) {
  case values {
    option.None -> Ok(False)
    option.Some([]) -> Ok(True)
    option.Some([v, ..]) ->
      case string.lowercase(v) {
        "true" | "1" | "yes" -> Ok(True)
        "false" | "0" | "no" -> Ok(False)
        _ -> Error("Expected a boolean, got '" <> v <> "'")
      }
  }
}

fn decode_int(
  values: option.Option(List(String)),
) -> Result(option.Option(Int), String) {
  case values {
    option.None -> Ok(option.None)
    option.Some([]) -> Error("No value provided")
    option.Some([v, ..]) ->
      case int.parse(v) {
        Ok(v) -> Ok(option.Some(v))
        Error(_) -> Error("Expected an integer, got '" <> v <> "'")
      }
  }
}

fn decode_string(
  values: option.Option(List(String)),
) -> Result(option.Option(String), String) {
  case values {
    option.None -> Ok(option.None)
    option.Some([]) -> Error("No value provided")
    option.Some([v, ..]) -> Ok(option.Some(v))
  }
}

pub fn required(
  flag_decoder: FlagDecoder(option.Option(a)),
  default_value: a,
) -> FlagDecoder(a) {
  flag_decoder
  |> then(default_value, fn(opt_value) {
    case opt_value {
      option.None -> Error("This argument is required !")
      option.Some(v) -> Ok(v)
    }
  })
}

pub fn map(flag_decoder: FlagDecoder(a), map_fn: fn(a) -> b) -> FlagDecoder(b) {
  let decode_fn = fn(values: option.Option(List(String))) -> Result(b, String) {
    flag_decoder.decode_fn(values)
    |> result.map(map_fn)
  }

  FlagDecoder(default_value: map_fn(flag_decoder.default_value), decode_fn:)
}

pub fn then(
  flag_decoder: FlagDecoder(a),
  default_value: b,
  then_fn: fn(a) -> Result(b, String),
) -> FlagDecoder(b) {
  let decode_fn = fn(values: option.Option(List(String))) -> Result(b, String) {
    flag_decoder.decode_fn(values)
    |> result.try(then_fn)
  }

  FlagDecoder(default_value:, decode_fn:)
}

pub fn run(command: Command(a), args: List(String)) -> Result(a, Nil) {
  use <- help_actions(command, args)

  case find_action(command.actions, args) {
    Ok(#(action, args)) ->
      args_to_dict(args)
      |> action.decoder.decode()
      |> tuple_to_result()
      |> result.map_error(fn(err) {
        print_errors(err)
        print_help_action(action)
      })
    Error(_) -> {
      print_help(command)
      Error(Nil)
    }
  }
}

fn help_actions(
  command: Command(a),
  args: List(String),
  exec_action: fn() -> Result(a, Nil),
) {
  case args {
    ["help"] | ["--help"] -> {
      print_help(command)
      Error(Nil)
    }
    ["help", ..action_args] -> {
      case find_action(command.actions, action_args) {
        Ok(#(action, _)) -> {
          print_help_action(action)
          Error(Nil)
        }
        Error(_) -> {
          print_help(command)
          Error(Nil)
        }
      }
    }
    _ -> exec_action()
  }
}

fn print_help(command: Command(a)) -> Nil {
  { command.name <> "\n" <> command.description }
  |> box_text(80)
  |> io.println

  io.println("")
  io.println("Usage: gleam run -m " <> command.name <> " <action> [<flags>]")
  io.println("")
  io.println("Available actions:")
  list.each(command.actions |> list.reverse, fn(action) {
    let action_path = action.action_path |> string.join(" ")
    io.println("  " <> action_path <> " - " <> action.help)
  })

  io.println("")
  io.println(
    "Use `"
    <> command.name
    <> " help <action>` to get more information about an action.",
  )
}

fn print_help_action(action: Action(a)) -> Nil {
  { action.action_path |> string.join(" ") <> "\n" <> action.help }
  |> box_text(80)
  |> io.println

  io.println("")
  io.println("Available flags:")
  list.each(action.decoder.flag_defs, fn(flag) {
    {
      justify_left(print_flag(flag.name) <> " " <> flag.type_, 20)
      <> " - "
      <> flag.description
      <> "\n"
      <> string.repeat(" ", 24)
      <> "Aliases: "
      <> flag.aliases |> list.map(print_flag) |> string.join(", ")
    }
    |> io.println()
  })
}

fn print_flag(flag_name: String) {
  case string.length(flag_name) {
    0 -> "/!\\ Flag name should not be empty"
    1 -> "-" <> flag_name
    _ -> "--" <> flag_name
  }
}

fn justify_left(text: String, width: Int) {
  case string.length(text) {
    i if i < width -> text <> string.repeat(" ", width - i)
    _ -> text
  }
}

fn box_text(text: String, max_width: Int) -> String {
  let lines = center_text(text, max_width - 4) |> string.split("\n")
  let actual_width = string.length(lines |> list.first |> result.unwrap("")) + 4
  let top_bottom_line = string.repeat("=", actual_width)

  box_lines(lines, [top_bottom_line])
  |> list.prepend(top_bottom_line)
  |> list.reverse()
  |> string.join("\n")
}

fn box_lines(lines: List(String), boxed: List(String)) -> List(String) {
  case lines {
    [] -> boxed
    [line, ..rest] -> box_lines(rest, ["= " <> line <> " =", ..boxed])
  }
}

fn center_text(text: String, max_width: Int) -> String {
  let lines = string.split(text, "\n")
  let max_line_length =
    list.fold(lines, 0, fn(acc, line) { int.max(acc, string.length(line)) })
    |> int.min(max_width)

  lines
  |> list.flat_map(fn(line) {
    let line_length = string.length(line)

    case line_length {
      v if v > max_line_length ->
        string.split(line, " ")
        |> words_to_lines(max_line_length)
        |> list.map(do_padding(_, max_line_length))
      _ -> [do_padding(line, max_line_length)]
    }
  })
  |> string.join("\n")
}

fn do_padding(text: String, width: Int) -> String {
  let padding = width - string.length(text)
  let left_padding = padding / 2
  let right_padding = padding - left_padding
  let left_spaces = string.repeat(" ", left_padding)
  let right_spaces = string.repeat(" ", right_padding)
  left_spaces <> text <> right_spaces
}

fn words_to_lines(words: List(String), max_line_length: Int) -> List(String) {
  list.fold(words, [], fn(acc, word) {
    case acc {
      [] -> [word]
      [last_line, ..] ->
        case string.length(last_line) + string.length(word) {
          len if len <= max_line_length -> [last_line <> " " <> word, ..acc]
          _ -> [word, last_line, ..acc]
        }
    }
  })
  |> list.reverse()
}

fn print_errors(err: List(ParseError)) -> Nil {
  list.each(err, fn(error) {
    io.println_error("[Argument " <> error.argument <> "] " <> error.message)
  })
  io.println_error("")
}

fn find_action(
  actions_to_try: List(Action(a)),
  args: List(String),
) -> Result(#(Action(a), List(String)), Nil) {
  case actions_to_try {
    [] -> Error(Nil)
    [action, ..rest] -> {
      case get_action_args(action.action_path, args) {
        Ok(action_args) -> Ok(#(action, action_args))
        Error(_) -> find_action(rest, args)
      }
    }
  }
}

fn get_action_args(
  action_path: List(String),
  args: List(String),
) -> Result(List(String), Nil) {
  case action_path, args {
    [], args_rest -> Ok(args_rest)
    [head, ..tail], [head2, ..tail2] if head == head2 ->
      get_action_args(tail, tail2)
    _, _ -> Error(Nil)
  }
}

pub fn args_to_dict(args: List(String)) -> dict.Dict(String, List(String)) {
  args_list_to_dict(args, dict.new())
}

fn args_list_to_dict(
  args: List(String),
  dict: dict.Dict(String, List(String)),
) -> dict.Dict(String, List(String)) {
  case args {
    [] -> dict
    ["--" <> name] | ["-" <> name] -> dict |> add_to_dict(#(name, option.None))
    [_] -> dict
    ["--" <> name, "-" <> arg2, ..rest] | ["-" <> name, "-" <> arg2, ..rest] ->
      args_list_to_dict(
        ["-" <> arg2, ..rest],
        dict |> add_to_dict(#(name, option.None)),
      )
    ["--" <> name, arg2, ..rest] | ["-" <> name, arg2, ..rest] ->
      args_list_to_dict(rest, dict |> add_to_dict(#(name, option.Some(arg2))))
    [_arg1, ..rest] -> args_list_to_dict(rest, dict)
  }
}

fn add_to_dict(
  dict: dict.Dict(String, List(String)),
  kv: #(String, option.Option(String)),
) -> dict.Dict(String, List(String)) {
  let #(key, value) = kv

  dict
  |> dict.upsert(key, fn(prev_v) {
    case prev_v, value {
      option.None, option.None -> []
      option.None, option.Some(v) -> [v]
      option.Some(prev_v), option.None -> prev_v
      option.Some(prev_v), option.Some(v) -> [v, ..prev_v]
    }
  })
}
