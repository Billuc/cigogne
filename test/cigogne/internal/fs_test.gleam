import cigogne/internal/fs
import cigogne/internal/migrations
import cigogne/types
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import simplifile
import tempo/naive_datetime

pub fn parse_mig_path_test() {
  "priv/migrations/20241217205656-MigrationTest.sql"
  |> fs.parse_file_name
  |> should.be_ok
  |> should.equal(#(
    naive_datetime.literal("2024-12-17 20:56:56"),
    "MigrationTest",
  ))
}

pub fn parse_mig_path_no_slash_test() {
  "20241217205757-SecondMigration.sql"
  |> fs.parse_file_name
  |> should.be_ok
  |> should.equal(#(
    naive_datetime.literal("2024-12-17 20:57:57"),
    "SecondMigration",
  ))
}

pub fn parse_not_sql_should_fail_test() {
  "20241217205757-NotSql.test"
  |> fs.parse_file_name
  |> should.be_error
  |> should.equal(types.FileNameError("20241217205757-NotSql.test"))
}

pub fn parse_no_dash_should_fail_test() {
  "20241217205757NoDash.sql"
  |> fs.parse_file_name
  |> should.be_error
  |> should.equal(types.FileNameError("20241217205757NoDash.sql"))
}

pub fn parse_int_id_should_fail_test() {
  "5-NotATimestamp.sql"
  |> fs.parse_file_name
  |> should.be_error
  |> should.equal(types.DateParseError("5"))
}

pub fn parse_not_a_timestamp_id_should_fail_test() {
  "Today-NotATimestamp.sql"
  |> fs.parse_file_name
  |> should.be_error
  |> should.equal(types.DateParseError("Today"))
}

pub fn parse_name_too_long_should_fail_test() {
  { "20241217205757-" <> string.repeat("a", 256) <> ".sql" }
  |> fs.parse_file_name
  |> should.be_error
  |> should.equal(types.NameTooLongError(string.repeat("a", 256)))
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

pub fn split_queries_with_literal_test() {
  "
--- migration:up
INSERT INTO foo VALUES ('titi;toto');
--- migration:down
DELETE FROM foo WHERE name = $$Dianne's horse;tutu$$;
--- migration:end
  "
  |> fs.parse_migration_file
  |> should.be_ok
  |> should.equal(
    #(["INSERT INTO foo VALUES ('titi;toto');"], [
      "DELETE FROM foo WHERE name = $$Dianne's horse;tutu$$;",
    ]),
  )
}

pub fn split_complex_queries_test() {
  "
--- migration:up
INSERT INTO foo VALUES ('titi;toto');
SELECT 'foo'
'bar';
SELECT 'Dianne''s horse'
--- migration:down
DELETE FROM foo WHERE name = $$Dianne's horse;tutu$$;
SELECT * from foo WHERE id = $1;
$function$
BEGIN
    RETURN ($1 ~ $q$[\\t\\r\\n\\v\\]$q$);
END;
$function$
--- migration:end
  "
  |> fs.parse_migration_file
  |> should.be_ok
  |> should.equal(
    #(
      [
        "INSERT INTO foo VALUES ('titi;toto');", "SELECT 'foo'\n'bar';",
        "SELECT 'Dianne''s horse';",
      ],
      [
        "DELETE FROM foo WHERE name = $$Dianne's horse;tutu$$;",
        "SELECT * from foo WHERE id = $1;",
        "$function$\nBEGIN\n    RETURN ($1 ~ $q$[\\t\\r\\n\\v\\]$q$);\nEND;\n$function$;",
      ],
    ),
  )
}

pub fn split_queries_example_from_issue_test() {
  "
--- migration:up
CREATE FUNCTION set_current_timestamp_updated_at()
    RETURNS TRIGGER AS $$
DECLARE
_new record;
BEGIN
  _new := NEW;
  _new.updated_at = now();
RETURN _new;
END;
$$ LANGUAGE plpgsql;
--- migration:down
SELECT 1;
--- migration:end
  "
  |> fs.parse_migration_file
  |> should.be_ok
  |> should.equal(
    #(
      [
        "CREATE FUNCTION set_current_timestamp_updated_at()
    RETURNS TRIGGER AS $$
DECLARE
_new record;
BEGIN
  _new := NEW;
  _new.updated_at = now();
RETURN _new;
END;
$$ LANGUAGE plpgsql;",
      ],
      ["SELECT 1;"],
    ),
  )
}

pub fn simplifile_read_directory_test() {
  use <- setup_and_teardown_migrations()

  simplifile.read_directory("priv/migrations")
  |> should.be_ok
  |> should.equal(["20240101123246-Test1.sql", "20240922065413-Test2.sql"])

  Ok(Nil)
}

pub fn get_migrations_test() {
  use <- setup_and_teardown_migrations()

  let migs =
    fs.get_migrations()
    |> should.be_ok()
    |> list.sort(migrations.compare_migrations)
  use #(first, rest) <- result.try(
    list.pop(migs, fn(_) { True })
    |> result.replace_error("No migration found !"),
  )
  use second <- result.map(
    list.first(rest) |> result.replace_error("Only one migration found !"),
  )

  first.timestamp |> should.equal(naive_datetime.literal("2024-01-01 12:32:46"))
  first.name |> should.equal("Test1")
  first.queries_up
  |> should.equal(["create table todos(id uuid primary key, title text);"])
  first.queries_down |> should.equal(["drop table todos;"])

  second.timestamp
  |> should.equal(naive_datetime.literal("2024-09-22 06:54:13"))
  second.name |> should.equal("Test2")
  second.queries_up
  |> should.equal([
    "create table tags(id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY, tag text not null);",
    "alter table todos add column tag integer references tags(id);",
  ])
  second.queries_down
  |> should.equal(["alter table todos drop column tag;", "drop table tags;"])
}

fn setup_and_teardown_migrations(test_cb: fn() -> Result(a, b)) {
  let dir = "priv/migrations"
  let mig_1 = dir <> "/20240101123246-Test1.sql"
  let mig_2 = dir <> "/20240922065413-Test2.sql"
  let assert Ok(_) = simplifile.create_directory_all(dir)
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
  create table tags(id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY, tag text not null);
  alter table todos add column tag integer references tags(id);
  --- migration:down
  alter table todos drop column tag;
  drop table tags;
  --- migration:end
  ",
    )

  let test_result = test_cb()

  let assert Ok(_) = simplifile.delete("priv")

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

pub fn create_new_migration_file_test() {
  use <- setup_and_teardown_migrations()

  let timestamp = naive_datetime.literal("2024-11-17 18:36:41")

  fs.create_new_migration_file(timestamp, "MyNewMigration")
  |> should.be_ok
  simplifile.read("priv/migrations/20241117183641-MyNewMigration.sql")
  |> should.be_ok
  |> should.equal(
    "--- migration:up

--- migration:down

--- migration:end",
  )

  Ok(Nil)
}

pub fn create_new_migration_create_priv_migrations_folder() {
  let timestamp = naive_datetime.literal("2024-11-17 18:36:41")
  fs.create_new_migration_file(timestamp, "MyNewMigration")
  |> should.be_ok

  simplifile.is_directory("priv/migrations")
  |> should.be_ok
  |> should.equal(True)

  simplifile.delete("priv")
}

pub fn create_new_migration_returns_error_if_name_too_long_test() {
  use <- setup_and_teardown_migrations()

  let timestamp = naive_datetime.literal("2024-11-17 18:36:41")

  fs.create_new_migration_file(timestamp, string.repeat("a", 256))
  |> should.be_error
  |> should.equal(types.NameTooLongError(string.repeat("a", 256)))

  Ok(Nil)
}
