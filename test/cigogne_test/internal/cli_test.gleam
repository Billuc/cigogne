import cigogne/config
import cigogne/internal/cli
import gleam/option

pub fn new_requires_name_flag_test() {
  let args = ["new", "--name", "Test"]
  let args_no_name = ["new"]

  assert cli.get_action("cigogne", args)
    == Ok(cli.NewMigration(
      config.MigrationsConfig(
        ..config.default_config.migrations,
        no_hash_check: option.Some(False),
      ),
      "Test",
    ))
  assert cli.get_action("cigogne", args_no_name) == Error(Nil)
}
