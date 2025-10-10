import cigogne/internal/fs
import cigogne/internal/parser_formatter
import cigogne/migration
import gleam/string
import gleam/time/timestamp

pub fn parse_mig_path_test() {
  let file =
    fs.File(
      "priv/migrations/20241217205656-MigrationTest.sql",
      "
--- migration:up
CREATE TABLE test (id INTEGER);
--- migration:down
DROP TABLE test;
--- migration:end
    ",
    )

  let assert Ok(migration) = parser_formatter.parse(file)

  let assert Ok(expected_ts) = timestamp.parse_rfc3339("2024-12-17T20:56:56Z")
  assert migration.timestamp == expected_ts
  assert migration.name == "MigrationTest"
  assert migration.path == "priv/migrations/20241217205656-MigrationTest.sql"
}

pub fn parse_mig_path_no_slash_test() {
  let file =
    fs.File(
      "20241217205757-SecondMigration.sql",
      "
--- migration:up
CREATE TABLE test (id INTEGER);
--- migration:down
DROP TABLE test;
--- migration:end
    ",
    )

  let assert Ok(migration) = parser_formatter.parse(file)

  let assert Ok(expected_ts) = timestamp.parse_rfc3339("2024-12-17T20:57:57Z")
  assert migration.timestamp == expected_ts
  assert migration.name == "SecondMigration"
  assert migration.path == "20241217205757-SecondMigration.sql"
}

pub fn parse_not_sql_should_fail_test() {
  let file =
    fs.File("20241217205757-NotSql.test", "CREATE TABLE test (id INTEGER);")

  let assert Error(err) = parser_formatter.parse(file)

  assert err == parser_formatter.NotASQLFile("20241217205757-NotSql.test")
}

pub fn parse_no_dash_should_fail_test() {
  let file =
    fs.File("20241217205757NoDash.sql", "CREATE TABLE test (id INTEGER);")

  let assert Error(err) = parser_formatter.parse(file)

  assert err == parser_formatter.WrongFormat("20241217205757NoDash")
}

pub fn parse_int_id_should_fail_test() {
  let file = fs.File("5-NotATimestamp.sql", "CREATE TABLE test (id INTEGER);")

  let assert Error(err) = parser_formatter.parse(file)

  assert err == parser_formatter.WrongFormat("5-NotATimestamp")
}

pub fn parse_not_a_timestamp_id_should_fail_test() {
  let file =
    fs.File("Today-NotATimestamp.sql", "CREATE TABLE test (id INTEGER);")

  let assert Error(err) = parser_formatter.parse(file)

  assert err == parser_formatter.WrongFormat("Today-NotATimestamp")
}

pub fn parse_name_too_long_should_fail_test() {
  let file =
    fs.File(
      "20241217205757-" <> string.repeat("a", 256) <> ".sql",
      "CREATE TABLE test (id INTEGER);",
    )

  let assert Error(err) = parser_formatter.parse(file)

  assert err
    == parser_formatter.MigrationError(
      migration.NameTooLongError(string.repeat("a", 256)),
    )
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
  let file = fs.File("20241217205757-MigrationTest.sql", content)

  let assert Ok(migration) = parser_formatter.parse(file)

  assert migration.path == "20241217205757-MigrationTest.sql"
  let assert Ok(expected_ts) = timestamp.parse_rfc3339("2024-12-17T20:57:57Z")
  assert migration.timestamp == expected_ts
  assert migration.name == "MigrationTest"
  assert migration.queries_up
    == [
      "CREATE TABLE IF NOT EXISTS users(id UUID PRIMARY KEY, name TEXT NOT NULL);",
    ]
  assert migration.queries_down == ["DROP TABLE users;"]
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
  let file = fs.File("20241217205757-MigrationTest.sql", content)

  let assert Ok(migration) = parser_formatter.parse(file)

  assert migration.path == "20241217205757-MigrationTest.sql"
  let assert Ok(expected_ts) = timestamp.parse_rfc3339("2024-12-17T20:57:57Z")
  assert migration.timestamp == expected_ts
  assert migration.name == "MigrationTest"
  assert migration.queries_up == ["foo;"]
  assert migration.queries_down == ["bar;"]
}

pub fn error_if_no_migration_up_test() {
  let content =
    "
--- migration:up
--- migration:down
bar;
--- migration:end
  "
  let file = fs.File("20241217205757-MigrationTest.sql", content)

  let assert Error(err) = parser_formatter.parse(file)

  assert err
    == parser_formatter.EmptyUpMigration("20241217205757-MigrationTest.sql")
}

pub fn error_if_no_migration_down_test() {
  let content =
    "
--- migration:up
bar;
--- migration:down
--- migration:end
  "
  let file = fs.File("20241217205757-MigrationTest.sql", content)

  let assert Error(err) = parser_formatter.parse(file)

  assert err
    == parser_formatter.EmptyDownMigration("20241217205757-MigrationTest.sql")
}

pub fn error_if_guard_missing_test() {
  let content =
    "
--- migration:up
--- migration:down
bar;
  "
  let file = fs.File("20241217205757-MigrationTest.sql", content)

  let assert Error(err) = parser_formatter.parse(file)

  assert err
    == parser_formatter.MissingEndGuard("20241217205757-MigrationTest.sql")
}

pub fn split_queries_test() {
  let content =
    "
--- migration:up
foo;bar;
--- migration:down
baz;
abc;
--- migration:end
  "
  let file = fs.File("20241217205757-MigrationTest.sql", content)

  let assert Ok(migration) = parser_formatter.parse(file)

  assert migration.queries_up == ["foo;", "bar;"]
  assert migration.queries_down == ["baz;", "abc;"]
}

pub fn split_queries_with_literal_test() {
  let content =
    "
--- migration:up
INSERT INTO foo VALUES ('titi;toto');
--- migration:down
DELETE FROM foo WHERE name = $$Dianne's horse;tutu$$;
--- migration:end
  "
  let file = fs.File("20241217205757-MigrationTest.sql", content)

  let assert Ok(migration) = parser_formatter.parse(file)

  assert migration.queries_up == ["INSERT INTO foo VALUES ('titi;toto');"]
  assert migration.queries_down
    == ["DELETE FROM foo WHERE name = $$Dianne's horse;tutu$$;"]
}

pub fn split_complex_queries_test() {
  let content =
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
  let file = fs.File("20241217205757-MigrationTest.sql", content)

  let assert Ok(migration) = parser_formatter.parse(file)

  assert migration.queries_up
    == [
      "INSERT INTO foo VALUES ('titi;toto');", "SELECT 'foo'\n'bar';",
      "SELECT 'Dianne''s horse';",
    ]
  assert migration.queries_down
    == [
      "DELETE FROM foo WHERE name = $$Dianne's horse;tutu$$;",
      "SELECT * from foo WHERE id = $1;",
      "$function$\nBEGIN\n    RETURN ($1 ~ $q$[\\t\\r\\n\\v\\]$q$);\nEND;\n$function$;",
    ]
}

pub fn split_queries_example_from_issue_test() {
  let content =
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
  let file = fs.File("20241217205757-MigrationTest.sql", content)

  let assert Ok(migration) = parser_formatter.parse(file)

  assert migration.queries_up
    == [
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
    ]
  assert migration.queries_down == ["SELECT 1;"]
}

pub fn quote_in_comment_test() {
  let content =
    "
--- migration:up
-- What doesn't kill you makes you stronger
  CREATE TABLE books(id SERIAL);
--- migration:down
  DROP TABLE books;
--- migration:end
  "
  let file = fs.File("20251010100203-MigrationTest.sql", content)

  let assert Ok(migration) = parser_formatter.parse(file)

  assert migration.queries_up == ["CREATE TABLE books(id SERIAL);"]
  assert migration.queries_down == ["DROP TABLE books;"]
}

pub fn c_style_comments_test() {
  let content =
    "
--- migration:up
  /*
    * This is a test
    * of a multiline comment
    */
    SELECT 1;
    /*
    * I can  write -- comments here
    */
    -- But multiline here /* would break stuff

--- migration:down
    SELECT 1;
--- migration:end
    "
  let file = fs.File("20251010102930-MigrationTest.sql", content)

  let assert Ok(migration) = parser_formatter.parse(file)

  assert migration.queries_up == ["SELECT 1;"]
  assert migration.queries_down == ["SELECT 1;"]
}
