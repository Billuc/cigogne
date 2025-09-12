import cigogne
import cigogne/internal/utils
import cigogne/types
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

pub fn new_migration_test() {
  let priv_test_folder = "priv/test"
  let test_migrations_folder = priv_test_folder <> "/test_migrations"

  let assert Ok(True) = simplifile.is_directory(priv_test_folder)
  let assert Ok(False) = simplifile.is_directory(test_migrations_folder)
}

pub fn create_zero_migration_test() {
  let migration = cigogne.create_zero_migration("test_zero", ["abc"], ["def"])

  migration
  |> should.equal(types.Migration(
    "",
    utils.epoch(),
    "test_zero",
    ["abc"],
    ["def"],
    "BEF57EC7F53A6D40BEB640A780A639C83BC29AC8A9816F1FC6C5C6DCD93C4721",
  ))

  migration
  |> cigogne.is_zero_migration()
  |> should.be_true
}
