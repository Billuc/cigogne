import cigogne/internal/cli
import gleam/option

pub fn new_requires_name_flag_test() {
  let args = ["new", "--name", "Test"]
  let args_no_name = ["new"]

  assert cli.get_action(args) == Ok(cli.NewMigration(option.None, "Test"))
  assert cli.get_action(args_no_name) == Error(Nil)
}
