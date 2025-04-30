import cigogne/internal/migrations
import cigogne/internal/utils
import cigogne/types
import gleam/list
import gleeunit/should
import tempo/naive_datetime

pub fn find_migration_test() {
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
  |> migrations.find_migration(types.Migration(
    "",
    naive_datetime.literal("2024-12-17 21:02:02"),
    "Test2",
    [],
    [],
    "",
  ))
  |> should.be_ok
  |> should.equal(types.Migration(
    "",
    naive_datetime.literal("2024-12-17 21:02:02"),
    "Test2",
    ["up2.1", "up2.2"],
    ["down2.1", "down2.2"],
    "",
  ))
}

pub fn migration_not_found_if_wrong_timestamp_test() {
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
  |> migrations.find_migration(types.Migration(
    "",
    naive_datetime.literal("2024-12-17 21:03:03"),
    "Test2",
    [],
    [],
    "",
  ))
  |> should.be_error
  |> should.equal(types.MigrationNotFoundError(
    naive_datetime.literal("2024-12-17 21:03:03"),
    "Test2",
  ))
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
  |> migrations.find_migration(types.Migration(
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
  |> list.sort(migrations.compare_migrations)
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

  migrations.find_first_non_applied_migration(migrations, applied_migrations)
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

  migrations.find_first_non_applied_migration(migrations, applied_migrations)
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

  migrations.find_first_non_applied_migration(migrations, applied_migrations)
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

  migrations.find_first_non_applied_migration(migrations, applied_migrations)
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

  migrations.find_all_non_applied_migration(migrations, applied_migrations)
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

  migrations.find_n_migrations_to_apply(migrations, applied_migrations, 2)
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

  migrations.find_n_migrations_to_apply(migrations, applied_migrations, -2)
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
  |> migrations.is_zero_migration()
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
  |> migrations.is_zero_migration()
  |> should.be_false

  types.Migration(
    "",
    naive_datetime.now_utc(),
    "test",
    ["CREATE TABLE test();"],
    ["DROP TABLE test;"],
    "fde7050fe128b1ccf71703ab7463748a481fc1d347ab17ea3eaee56f4a2cd96f",
  )
  |> migrations.is_zero_migration()
  |> should.be_false
}
