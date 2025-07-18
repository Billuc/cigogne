import cigogne/internal/migration_parser
import cigogne/types
import gleam/string
import gleeunit/should
import tempo/naive_datetime

pub fn parse_mig_path_test() {
  let assert Ok(res) =
    "priv/migrations/20241217205656-MigrationTest.sql"
    |> migration_parser.parse_file_name

  assert res.0 == naive_datetime.literal("2024-12-17 20:56:56")
  assert res.1 == "MigrationTest"
}

pub fn parse_mig_path_no_slash_test() {
  let assert Ok(res) =
    "20241217205757-SecondMigration.sql"
    |> migration_parser.parse_file_name

  assert res.0 == naive_datetime.literal("2024-12-17 20:57:57")
  assert res.1 == "SecondMigration"
}

pub fn parse_not_sql_should_fail_test() {
  let assert Error(err) =
    "20241217205757-NotSql.test"
    |> migration_parser.parse_file_name

  assert err == types.FileNameError("20241217205757-NotSql.test")
}

pub fn parse_no_dash_should_fail_test() {
  let assert Error(err) =
    "20241217205757NoDash.sql"
    |> migration_parser.parse_file_name

  assert err == types.FileNameError("20241217205757NoDash.sql")
}

pub fn parse_int_id_should_fail_test() {
  let assert Error(err) =
    "5-NotATimestamp.sql"
    |> migration_parser.parse_file_name

  assert err == types.DateParseError("5")
}

pub fn parse_not_a_timestamp_id_should_fail_test() {
  let assert Error(err) =
    "Today-NotATimestamp.sql"
    |> migration_parser.parse_file_name

  assert err == types.DateParseError("Today")
}

pub fn parse_name_too_long_should_fail_test() {
  let filename = {
    "20241217205757-" <> string.repeat("a", 256) <> ".sql"
  }
  let assert Error(err) =
    filename
    |> migration_parser.parse_file_name

  assert err == types.NameTooLongError(string.repeat("a", 256))
}

pub fn parse_migration_file_test() {
  let content =
    "
--- migration:up
CREATE TABLE IF NOT EXISTS users(id UUID PRIMARY KEY, name TEXT NOT NULL);
--- migration:down
DROP TABLE users;
--- migration:end
  "
  let assert Ok(#(up, down)) =
    content
    |> migration_parser.parse_migration_file

  assert up
    == [
      "CREATE TABLE IF NOT EXISTS users(id UUID PRIMARY KEY, name TEXT NOT NULL);",
    ]
  assert down == ["DROP TABLE users;"]
}

pub fn text_after_end_tag_is_ignored_test() {
  let content =
    "
--- migration:up
foo;
--- migration:down
bar;
--- migration:end
baz;
  "

  let assert Ok(#(up, down)) =
    content
    |> migration_parser.parse_migration_file

  assert up == ["foo;"]
  assert down == ["bar;"]
}

pub fn error_if_no_migration_up_test() {
  let content =
    "
--- migration:up
--- migration:down
bar;
--- migration:end
  "
  let assert Error(err) =
    content
    |> migration_parser.parse_migration_file

  assert err == "migration:up is empty !"
}

pub fn error_if_no_migration_down_test() {
  "
--- migration:up
bar;
--- migration:down
--- migration:end
  "
  |> migration_parser.parse_migration_file
  |> should.be_error
  |> should.equal("migration:down is empty !")
}

pub fn error_if_guard_missing_test() {
  "
--- migration:up
--- migration:down
bar;
  "
  |> migration_parser.parse_migration_file
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
  |> migration_parser.parse_migration_file
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
  |> migration_parser.parse_migration_file
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
  |> migration_parser.parse_migration_file
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
  |> migration_parser.parse_migration_file
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
