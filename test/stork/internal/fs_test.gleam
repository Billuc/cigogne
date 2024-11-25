import gleam/list
import gleam/result
import gleeunit/should
import simplifile
import stork/internal/fs
import stork/types

pub fn parse_mig_path_test() {
  "src/migrations/1-MigrationTest.sql"
  |> fs.parse_file_name
  |> should.be_ok
  |> should.equal(#(1, "MigrationTest"))
}

pub fn parse_mig_path_no_slash_test() {
  "2-SecondMigration.sql"
  |> fs.parse_file_name
  |> should.be_ok
  |> should.equal(#(2, "SecondMigration"))
}

pub fn parse_not_sql_should_fail_test() {
  "3-NotSql.test"
  |> fs.parse_file_name
  |> should.be_error
  |> should.equal(types.FileNameError("3-NotSql.test"))
}

pub fn parse_no_dash_should_fail_test() {
  "4NoDash.sql"
  |> fs.parse_file_name
  |> should.be_error
  |> should.equal(types.FileNameError("4NoDash.sql"))
}

pub fn parse_not_an_int_should_fail_test() {
  "Five-NotAnInt.sql"
  |> fs.parse_file_name
  |> should.be_error
  |> should.equal(types.FileNameError("Five-NotAnInt.sql"))
}

pub fn parse_migration_file_test() {
  "
--- migration:up
CREATE TABLE IF NOT EXISTS users(id UUID PRIMARY KEY, name TEXT NOT NULL);
--- migration:down
DROP TABLE users;
--- migration:end  
  "
  |> fs.parse_migration_file
  |> should.be_ok
  |> should.equal(
    #(
      [
        "CREATE TABLE IF NOT EXISTS users(id UUID PRIMARY KEY, name TEXT NOT NULL);",
      ],
      ["DROP TABLE users;"],
    ),
  )
}

pub fn text_after_end_tag_is_ignored_test() {
  "
--- migration:up
foo;
--- migration:down  
bar;
--- migration:end
baz;
  "
  |> fs.parse_migration_file
  |> should.be_ok
  |> should.equal(#(["foo;"], ["bar;"]))
}

pub fn error_if_no_migration_up_test() {
  "
--- migration:up
--- migration:down
bar;
--- migration:end
  "
  |> fs.parse_migration_file
  |> should.be_error
  |> should.equal("migration:up is empty !")
}

pub fn error_if_no_migration_down_test() {
  "
--- migration:up
bar;
--- migration:down
--- migration:end
  "
  |> fs.parse_migration_file
  |> should.be_error
  |> should.equal("migration:down is empty !")
}

pub fn error_if_guard_missing_test() {
  "
--- migration:up
--- migration:down
bar;
  "
  |> fs.parse_migration_file
  |> should.be_error
  |> should.equal("File badly formatted: '--- migration:end' not found !")
}

pub fn split_queries_test() {
  "
--- migration:up
foo;bar;
--- migration:down
baz;
abc;
--- migration:end
  "
  |> fs.parse_migration_file
  |> should.be_ok
  |> should.equal(#(["foo;", "bar;"], ["baz;", "abc;"]))
}

pub fn find_migration_test() {
  [
    types.Migration("", 1, "Test1", [], []),
    types.Migration("", 2, "Test2", [], []),
  ]
  |> fs.find_migration(2)
  |> should.be_ok
  |> should.equal(types.Migration("", 2, "Test2", [], []))
}

pub fn migration_not_found_test() {
  [
    types.Migration("", 1, "Test1", [], []),
    types.Migration("", 2, "Test2", [], []),
  ]
  |> fs.find_migration(3)
  |> should.be_error
  |> should.equal(types.MigrationNotFoundError(3))
}

pub fn find_migrations_between_does_not_include_lower_if_going_up_test() {
  [
    types.Migration("", 1, "Test1", [], []),
    types.Migration("", 2, "Test2", [], []),
    types.Migration("", 3, "Test3", [], []),
    types.Migration("", 4, "Test4", [], []),
    types.Migration("", 5, "Test5", [], []),
  ]
  |> fs.find_migrations_between(2, 4)
  |> should.be_ok
  |> should.equal([
    types.Migration("", 3, "Test3", [], []),
    types.Migration("", 4, "Test4", [], []),
  ])
}

pub fn find_migrations_between_include_all_if_going_down_test() {
  [
    types.Migration("", 1, "Test1", [], []),
    types.Migration("", 2, "Test2", [], []),
    types.Migration("", 3, "Test3", [], []),
    types.Migration("", 4, "Test4", [], []),
    types.Migration("", 5, "Test5", [], []),
  ]
  |> fs.find_migrations_between(3, 1)
  |> should.be_ok
  |> should.equal([
    types.Migration("", 3, "Test3", [], []),
    types.Migration("", 2, "Test2", [], []),
    types.Migration("", 1, "Test1", [], []),
  ])
}

pub fn find_migrations_between_fails_if_one_missing_test() {
  [
    types.Migration("", 1, "Test1", [], []),
    types.Migration("", 2, "Test2", [], []),
    types.Migration("", 4, "Test4", [], []),
    types.Migration("", 5, "Test5", [], []),
  ]
  |> fs.find_migrations_between(1, 4)
  |> should.be_error
  |> should.equal(types.MigrationNotFoundError(3))
}

pub fn get_migrations_test() {
  use <- setup_and_teardown_migrations()

  let migs =
    fs.get_migrations()
    |> should.be_ok()
    |> list.reverse
  use #(first, rest) <- result.try(
    list.pop(migs, fn(_) { True })
    |> result.replace_error("No migration found !"),
  )
  use second <- result.map(
    list.first(rest) |> result.replace_error("Only one migration found !"),
  )

  first.number |> should.equal(1)
  first.name |> should.equal("Test1")
  first.queries_up
  |> should.equal(["create table todos(id uuid primary key, title text);"])
  first.queries_down |> should.equal(["drop table todos;"])

  second.number |> should.equal(2)
  second.name |> should.equal("Test2")
  second.queries_up
  |> should.equal([
    "create table tags(id serial primary key, tag text not null);",
    "alter table todos add column tag serial references tags(id);",
  ])
  second.queries_down
  |> should.equal(["alter table todos drop column tag;", "drop table tags;"])
}

fn setup_and_teardown_migrations(test_cb: fn() -> Result(a, b)) {
  let dir = "./test/migrations"
  let mig_1 = dir <> "/1-Test1.sql"
  let mig_2 = dir <> "/2-Test2.sql"
  let assert Ok(_) = simplifile.create_directory(dir)
  let assert Ok(_) = simplifile.create_file(mig_1)
  let assert Ok(_) = simplifile.create_file(mig_2)
  let assert Ok(_) =
    simplifile.write(
      mig_1,
      "
  --- migration:up
  create table todos(id uuid primary key, title text);
  --- migration:down
  drop table todos;
  --- migration:end
  ",
    )
  let assert Ok(_) =
    simplifile.write(
      mig_2,
      "
  --- migration:up
  create table tags(id serial primary key, tag text not null);
  alter table todos add column tag serial references tags(id);
  --- migration:down
  alter table todos drop column tag;
  drop table tags;
  --- migration:end
  ",
    )

  let test_result = test_cb()

  let assert Ok(_) = simplifile.delete(dir)

  test_result |> should.be_ok()
}

pub fn read_schema_file_test() {
  let assert Ok(_) = simplifile.create_file("./sql.schema")
  let assert Ok(_) = simplifile.write("./sql.schema", "my test schema")

  let result = fs.read_schema_file()

  let assert Ok(_) = simplifile.delete("./sql.schema")

  result
  |> should.be_ok
  |> should.equal("my test schema")
}

pub fn write_schema_file_test() {
  let result_write = fs.write_schema_file("this is a test")
  let result_read = fs.read_schema_file()

  let assert Ok(_) = simplifile.delete("./sql.schema")

  result_write |> should.be_ok
  result_read |> should.be_ok |> should.equal("this is a test")
}
