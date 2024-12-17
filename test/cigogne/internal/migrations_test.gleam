import cigogne/internal/migrations
import cigogne/types
import gleam/list
import gleam/result
import gleeunit/should
import simplifile
import tempo/naive_datetime

pub fn find_migration_test() {
  [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:01:01"),
      "Test1",
      ["up1.1", "up1.2"],
      ["down1.1"],
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:02:02"),
      "Test2",
      ["up2.1", "up2.2"],
      ["down2.1", "down2.2"],
    ),
  ]
  |> migrations.find_migration(
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:02:02"),
      "Test2",
      [],
      [],
    ),
  )
  |> should.be_ok
  |> should.equal(
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:02:02"),
      "Test2",
      ["up2.1", "up2.2"],
      ["down2.1", "down2.2"],
    ),
  )
}

pub fn migration_not_found_if_wrong_timestamp_test() {
  [
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:01:01"),
      "Test1",
      ["up1.1", "up1.2"],
      ["down1.1"],
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:02:02"),
      "Test2",
      ["up2.1", "up2.2"],
      ["down2.1", "down2.2"],
    ),
  ]
  |> migrations.find_migration(
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:03:03"),
      "Test2",
      [],
      [],
    ),
  )
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
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:02:02"),
      "Test2",
      ["up2.1", "up2.2"],
      ["down2.1", "down2.2"],
    ),
  ]
  |> migrations.find_migration(
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:02:02"),
      "WRONG",
      [],
      [],
    ),
  )
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
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:01:01"),
      "Test1",
      [],
      [],
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:32:02"),
      "AAA",
      [],
      [],
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:02:02"),
      "Test2",
      [],
      [],
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
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:02:02"),
      "Test2",
      [],
      [],
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:02:02"),
      "Test22",
      [],
      [],
    ),
    types.Migration(
      "",
      naive_datetime.literal("2024-12-17 21:32:02"),
      "AAA",
      [],
      [],
    ),
  ])
}
