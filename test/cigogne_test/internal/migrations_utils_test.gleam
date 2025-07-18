import cigogne/internal/migrations_utils
import cigogne/types
import gleam/list
import gleam/string
import gleam/time/timestamp
import gleeunit/should

pub fn find_migration_test() {
  let assert Ok(first_ts) = timestamp.parse_rfc3339("2024-12-17T21:01:01Z")
  let assert Ok(second_ts) = timestamp.parse_rfc3339("2024-12-17T21:02:02Z")

  [
    types.Migration("", first_ts, "Test1", ["up1.1", "up1.2"], ["down1.1"], ""),
    types.Migration(
      "",
      second_ts,
      "Test2",
      ["up2.1", "up2.2"],
      ["down2.1", "down2.2"],
      "",
    ),
  ]
  |> migrations_utils.find_migration(types.Migration(
    "",
    second_ts,
    "Test2",
    [],
    [],
    "",
  ))
  |> should.be_ok
  |> should.equal(types.Migration(
    "",
    second_ts,
    "Test2",
    ["up2.1", "up2.2"],
    ["down2.1", "down2.2"],
    "",
  ))
}

pub fn migration_not_found_if_wrong_timestamp_test() {
  let assert Ok(first_ts) = timestamp.parse_rfc3339("2024-12-17T21:01:01Z")
  let assert Ok(second_ts) = timestamp.parse_rfc3339("2024-12-17T21:02:02Z")
  let assert Ok(third_ts) = timestamp.parse_rfc3339("2024-12-17T21:03:03Z")

  [
    types.Migration("", first_ts, "Test1", ["up1.1", "up1.2"], ["down1.1"], ""),
    types.Migration(
      "",
      second_ts,
      "Test2",
      ["up2.1", "up2.2"],
      ["down2.1", "down2.2"],
      "",
    ),
  ]
  |> migrations_utils.find_migration(types.Migration(
    "",
    third_ts,
    "Test2",
    [],
    [],
    "",
  ))
  |> should.be_error
  |> should.equal(types.MigrationNotFoundError(third_ts, "Test2"))
}

pub fn migration_not_found_if_wrong_name_test() {
  [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:01:01"),
      "Test1",
      ["up1.1", "up1.2"],
      ["down1.1"],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:02:02"),
      "Test2",
      ["up2.1", "up2.2"],
      ["down2.1", "down2.2"],
      "",
    ),
  ]
  |> migrations_utils.find_migration(types.Migration(
    "",
    naive_datetime.literal("2024-12-17 21:02:02"),
    "WRONG",
    [],
    [],
    "",
  ))
  |> should.be_error
  |> should.equal(types.MigrationNotFoundError(
    naive_datetime.literal("2024-12-17 21:02:02"),
    "WRONG",
  ))
}

pub fn compare_migrations_compares_by_timestamp_then_by_name_test() {
  [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:02:02"),
      "Test22",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:01:01"),
      "Test1",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:32:02"),
      "AAA",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:02:02"),
      "Test2",
      [],
      [],
      "",
    ),
  ]
  |> list.sort(migrations_utils.compare_migrations)
  |> should.equal([
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:01:01"),
      "Test1",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:02:02"),
      "Test2",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:02:02"),
      "Test22",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:32:02"),
      "AAA",
      [],
      [],
      "",
    ),
  ])
}

pub fn find_first_non_applied_migration_all_applied_test() {
  let migrations = [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:21"),
      "Test1",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:22"),
      "Test2",
      [],
      [],
      "",
    ),
  ]
  let applied_migrations = [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:21"),
      "Test1",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:22"),
      "Test2",
      [],
      [],
      "",
    ),
  ]

  migrations_utils.find_first_non_applied_migration(
    migrations,
    applied_migrations,
  )
  |> should.be_error
  |> should.equal(types.NoMigrationToApplyError)
}

pub fn test_find_first_non_applied_migration_is_last() {
  let migrations = [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:21"),
      "Test1",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:22"),
      "Test2",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:23"),
      "Test3",
      [],
      [],
      "",
    ),
  ]
  let applied_migrations = [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:21"),
      "Test1",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:22"),
      "Test2",
      [],
      [],
      "",
    ),
  ]

  migrations_utils.find_first_non_applied_migration(
    migrations,
    applied_migrations,
  )
  |> should.be_ok
  |> should.equal(types.Migration(
    "",
    naive_datetime.literal("2024-12-21 19:21:23"),
    "Test3",
    [],
    [],
    "",
  ))
}

pub fn find_first_non_applied_migration_is_not_last_test() {
  let migrations = [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:21"),
      "Test1",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:22"),
      "Test2",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:23"),
      "Test3",
      [],
      [],
      "",
    ),
  ]
  let applied_migrations = [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:21"),
      "Test1",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:23"),
      "Test3",
      [],
      [],
      "",
    ),
  ]

  migrations_utils.find_first_non_applied_migration(
    migrations,
    applied_migrations,
  )
  |> should.be_ok
  |> should.equal(types.Migration(
    "",
    naive_datetime.literal("2024-12-21 19:21:22"),
    "Test2",
    [],
    [],
    "",
  ))
}

pub fn find_first_non_applied_migration_skips_removed_migration_test() {
  let migrations = [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:21"),
      "Test1",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:23"),
      "Test3",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:24"),
      "Test4",
      [],
      [],
      "",
    ),
  ]
  let applied_migrations = [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:21"),
      "Test1",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:22"),
      "Test2",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:23"),
      "Test3",
      [],
      [],
      "",
    ),
  ]

  migrations_utils.find_first_non_applied_migration(
    migrations,
    applied_migrations,
  )
  |> should.be_ok
  |> should.equal(types.Migration(
    "",
    naive_datetime.literal("2024-12-21 19:21:24"),
    "Test4",
    [],
    [],
    "",
  ))
}

pub fn find_all_non_applied_migration_test() {
  let migrations = [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:21"),
      "Test1",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:22"),
      "Test2",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:23"),
      "Test3",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:24"),
      "Test4",
      [],
      [],
      "",
    ),
  ]
  let applied_migrations = [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:21"),
      "Test1",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:23"),
      "Test3",
      [],
      [],
      "",
    ),
  ]

  migrations_utils.find_all_non_applied_migration(
    migrations,
    applied_migrations,
  )
  |> should.be_ok
  |> should.equal([
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:22"),
      "Test2",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:24"),
      "Test4",
      [],
      [],
      "",
    ),
  ])
}

pub fn find_n_to_apply_positive_test() {
  let migrations = [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:21"),
      "Test1",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:22"),
      "Test2",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:23"),
      "Test3",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:24"),
      "Test4",
      [],
      [],
      "",
    ),
  ]
  let applied_migrations = [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:21"),
      "Test1",
      [],
      [],
      "",
    ),
  ]

  migrations_utils.find_n_migrations_to_apply(migrations, applied_migrations, 2)
  |> should.be_ok
  |> should.equal([
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:22"),
      "Test2",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:23"),
      "Test3",
      [],
      [],
      "",
    ),
  ])
}

pub fn find_n_migrations_to_apply_negative_test() {
  let migrations = [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:21"),
      "Test1",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:22"),
      "Test2",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:23"),
      "Test3",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:24"),
      "Test4",
      [],
      [],
      "",
    ),
  ]
  let applied_migrations = [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:21"),
      "Test1",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:22"),
      "Test2",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:23"),
      "Test3",
      [],
      [],
      "",
    ),
  ]

  migrations_utils.find_n_migrations_to_apply(
    migrations,
    applied_migrations,
    -2,
  )
  |> should.be_ok
  |> should.equal([
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:23"),
      "Test3",
      [],
      [],
      "",
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-21 19:21:22"),
      "Test2",
      [],
      [],
      "",
    ),
  ])
}

pub fn is_zero_migration_test() {
  types.Migration("", utils.tempo_epoch(), "", [], [], "")
  |> migrations_utils.is_zero_migration()
  |> should.be_true()
}

pub fn is_not_zero_migration_test() {
  types.Migration(
    "priv/migrations/01011970000000-test.sql",
    utils.tempo_epoch(),
    "test",
    ["CREATE TABLE test();"],
    ["DROP TABLE test;"],
    "fde7050fe128b1ccf71703ab7463748a481fc1d347ab17ea3eaee56f4a2cd96f",
  )
  |> migrations_utils.is_zero_migration()
  |> should.be_false

  types.Migration(
    "",
    instant.now()
      |> instant.as_utc_datetime()
      |> datetime.drop_offset(),
    "test",
    ["CREATE TABLE test();"],
    ["DROP TABLE test;"],
    "fde7050fe128b1ccf71703ab7463748a481fc1d347ab17ea3eaee56f4a2cd96f",
  )
  |> migrations_utils.is_zero_migration()
  |> should.be_false
}

pub fn create_zero_migration_test() {
  let name = "ZeroMigration"
  let queries_up = ["CREATE TABLE zero_migration();"]
  let queries_down = ["DROP TABLE zero_migration;"]

  let zero_mig =
    migrations_utils.create_zero_migration(name, queries_up, queries_down)

  assert zero_mig.path == ""
  assert zero_mig.name == name
  assert zero_mig.queries_up == queries_up
  assert zero_mig.queries_down == queries_down
  assert string.uppercase(zero_mig.sha256)
    == "FAE7D5FFD35013EB3CE95190A3AD407CF07D0F6F161607E29599A1597EA2891A"
}

pub fn to_migration_filename_test() {
  let timestamp = naive_datetime.literal("2024-12-17 20:56:56")
  let name = "MigrationTest"

  assert migrations_utils.to_migration_filename(timestamp, name)
    == "20241217205656-MigrationTest.sql"
}

pub fn check_name_valid_test() {
  let name = "ValidMigrationName"
  let assert Ok(validated_name) = migrations_utils.check_name(name)
  assert validated_name == name
}

pub fn check_name_too_long_test() {
  let name = string.repeat("a", 256)
  let assert Error(err) = migrations_utils.check_name(name)
  assert err == types.NameTooLongError(name)
}

pub fn format_migration_name_test() {
  let migration =
    types.Migration(
      "test_path",
      naive_datetime.literal("2025-07-18 11:22:33"),
      "ToFormat",
      [],
      [],
      "sha256hash",
    )

  let formatted_name = migrations_utils.format_migration_name(migration)

  assert formatted_name == "20250718112233-ToFormat"
}
