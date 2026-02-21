import cigogne/internal/utils
import cigogne/migration
import gleam/order
import gleam/string
import gleam/time/timestamp

pub fn new_migration_test() {
  let folder = "priv/migrations"
  let name = "NewMigration"
  let assert Ok(ts) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")

  let assert Ok(mig) = migration.new(folder, name, ts)

  assert mig.path == "priv/migrations/20241217210000-NewMigration.sql"
  assert mig.timestamp == ts
  assert mig.name == name
  assert mig.queries_up == []
  assert mig.queries_down == []
  assert mig.sha256 == ""
}

pub fn set_folder_test() {
  let assert Ok(ts) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let mig =
    migration.Migration(
      "",
      ts,
      "SetFolder",
      [],
      [],
      migration.MigrationOptions(False),
      "",
    )

  let mig_with_folder = migration.set_folder(mig, "priv/new_folder")

  assert mig_with_folder.path == "priv/new_folder/20241217210000-SetFolder.sql"
}

pub fn check_name_valid_test() {
  let name = "ValidName"
  let assert Ok(validated_name) = migration.check_name(name)
  assert validated_name == name
}

pub fn check_name_too_long_test() {
  let name = string.repeat("a", 256)
  let assert Error(err) = migration.check_name(name)
  assert err == migration.NameTooLongError(name)
}

pub fn to_fullname_test() {
  let assert Ok(ts) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let mig =
    migration.Migration(
      "",
      ts,
      "ToFullname",
      [],
      [],
      migration.MigrationOptions(False),
      "",
    )

  assert migration.to_fullname(mig) == "20241217210000-ToFullname"
}

pub fn compare_eq_test() {
  let assert Ok(ts) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let mig1 =
    migration.Migration(
      "",
      ts,
      "CompareEq",
      [],
      [],
      migration.MigrationOptions(False),
      "",
    )
  let mig2 =
    migration.Migration(
      "",
      ts,
      "CompareEq",
      [],
      [],
      migration.MigrationOptions(False),
      "",
    )

  assert migration.compare(mig1, mig2) == order.Eq
}

pub fn compare_lt_timestamp_test() {
  let assert Ok(ts1) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let assert Ok(ts2) = timestamp.parse_rfc3339("2024-12-17T21:01:00Z")
  let mig1 =
    migration.Migration(
      "",
      ts1,
      "CompareLt",
      [],
      [],
      migration.MigrationOptions(False),
      "",
    )
  let mig2 =
    migration.Migration(
      "",
      ts2,
      "CompareLt",
      [],
      [],
      migration.MigrationOptions(False),
      "",
    )

  assert migration.compare(mig1, mig2) == order.Lt
  assert migration.compare(mig2, mig1) == order.Gt
}

pub fn compare_lt_name_test() {
  let assert Ok(ts) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let mig1 =
    migration.Migration(
      "",
      ts,
      "AName",
      [],
      [],
      migration.MigrationOptions(False),
      "",
    )
  let mig2 =
    migration.Migration(
      "",
      ts,
      "BName",
      [],
      [],
      migration.MigrationOptions(False),
      "",
    )

  assert migration.compare(mig1, mig2) == order.Lt
  assert migration.compare(mig2, mig1) == order.Gt
}

pub fn merge_no_migrations_test() {
  let assert Error(err) = migration.merge([])
  assert err == migration.NothingToMergeError
}

pub fn merge_test() {
  let assert Ok(ts1) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let assert Ok(ts2) = timestamp.parse_rfc3339("2024-12-17T21:01:00Z")
  let assert Ok(ts3) = timestamp.parse_rfc3339("2024-12-17T21:02:00Z")
  let mig1 =
    migration.Migration(
      "",
      ts1,
      "Mig1",
      ["up1"],
      ["down1"],
      migration.MigrationOptions(False),
      "",
    )
  let mig2 =
    migration.Migration(
      "",
      ts2,
      "Mig2",
      ["up2"],
      ["down2"],
      migration.MigrationOptions(False),
      "",
    )
  let mig3 =
    migration.Migration(
      "",
      ts3,
      "Mig3",
      ["up3"],
      ["down3"],
      migration.MigrationOptions(False),
      "",
    )

  let assert Ok([queries]) = migration.merge([mig1, mig2, mig3])

  assert queries.0
    == [
      "\n--- " <> migration.to_fullname(mig1),
      "up1",
      "\n--- " <> migration.to_fullname(mig2),
      "up2",
      "\n--- " <> migration.to_fullname(mig3),
      "up3",
    ]
  assert queries.1
    == [
      "\n--- " <> migration.to_fullname(mig3),
      "down3",
      "\n--- " <> migration.to_fullname(mig2),
      "down2",
      "\n--- " <> migration.to_fullname(mig1),
      "down1",
    ]
  assert queries.2 == migration.MigrationOptions(False)
}

pub fn merge_with_disable_transaction_test() {
  let assert Ok(ts1) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let assert Ok(ts2) = timestamp.parse_rfc3339("2024-12-17T21:01:00Z")
  let assert Ok(ts3) = timestamp.parse_rfc3339("2024-12-17T21:02:00Z")
  let assert Ok(ts4) = timestamp.parse_rfc3339("2024-12-17T21:03:00Z")
  let mig1 =
    migration.Migration(
      "",
      ts1,
      "Mig1",
      ["up1"],
      ["down1"],
      migration.MigrationOptions(False),
      "",
    )
  let mig2 =
    migration.Migration(
      "",
      ts2,
      "Mig2",
      ["up2"],
      ["down2"],
      migration.MigrationOptions(False),
      "",
    )
  let mig3 =
    migration.Migration(
      "",
      ts3,
      "Mig3",
      ["up3"],
      ["down3"],
      migration.MigrationOptions(True),
      "",
    )
  let mig4 =
    migration.Migration(
      "",
      ts4,
      "Mig4",
      ["up4"],
      ["down4"],
      migration.MigrationOptions(False),
      "",
    )

  let assert Ok([q1, q2, q3]) = migration.merge([mig1, mig2, mig3, mig4])

  assert q1.0
    == [
      "\n--- " <> migration.to_fullname(mig1),
      "up1",
      "\n--- " <> migration.to_fullname(mig2),
      "up2",
    ]
  assert q1.1
    == [
      "\n--- " <> migration.to_fullname(mig2),
      "down2",
      "\n--- " <> migration.to_fullname(mig1),
      "down1",
    ]
  assert q1.2 == migration.MigrationOptions(False)

  assert q2.0 == ["\n--- " <> migration.to_fullname(mig3), "up3"]
  assert q2.1 == ["\n--- " <> migration.to_fullname(mig3), "down3"]
  assert q2.2 == migration.MigrationOptions(True)

  assert q3.0 == ["\n--- " <> migration.to_fullname(mig4), "up4"]
  assert q3.1 == ["\n--- " <> migration.to_fullname(mig4), "down4"]
  assert q3.2 == migration.MigrationOptions(False)
}

pub fn find_non_applied_test() {
  let assert Ok(ts1) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let assert Ok(ts2) = timestamp.parse_rfc3339("2024-12-17T21:01:00Z")
  let assert Ok(ts3) = timestamp.parse_rfc3339("2024-12-17T21:02:00Z")
  let mig1 =
    migration.Migration(
      "",
      ts1,
      "Mig1",
      ["up1"],
      ["down1"],
      migration.MigrationOptions(False),
      "",
    )
  let mig2 =
    migration.Migration(
      "",
      ts2,
      "Mig2",
      ["up2"],
      ["down2"],
      migration.MigrationOptions(False),
      "",
    )
  let mig3 =
    migration.Migration(
      "",
      ts3,
      "Mig3",
      ["up3"],
      ["down3"],
      migration.MigrationOptions(False),
      "",
    )
  let all = [mig1, mig2, mig3]
  let applied = [mig1, mig3]

  let non_applied = migration.find_unapplied(all, applied)

  assert non_applied == [mig2]
}

pub fn find_multiple_non_applied_test() {
  let assert Ok(ts1) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let assert Ok(ts2) = timestamp.parse_rfc3339("2024-12-17T21:01:00Z")
  let assert Ok(ts3) = timestamp.parse_rfc3339("2024-12-17T21:02:00Z")
  let mig1 =
    migration.Migration(
      "",
      ts1,
      "Mig1",
      ["up1"],
      ["down1"],
      migration.MigrationOptions(False),
      "",
    )
  let mig2 =
    migration.Migration(
      "",
      ts2,
      "Mig2",
      ["up2"],
      ["down2"],
      migration.MigrationOptions(False),
      "",
    )
  let mig3 =
    migration.Migration(
      "",
      ts3,
      "Mig3",
      ["up3"],
      ["down3"],
      migration.MigrationOptions(False),
      "",
    )
  let all = [mig1, mig2, mig3]
  let applied = [mig1]

  let non_applied = migration.find_unapplied(all, applied)

  assert non_applied == [mig2, mig3]
}

pub fn match_migrations_test() {
  let assert Ok(ts1) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let assert Ok(ts2) = timestamp.parse_rfc3339("2024-12-17T21:01:00Z")
  let assert Ok(ts3) = timestamp.parse_rfc3339("2024-12-17T21:02:00Z")

  let mig1 =
    migration.Migration(
      "path1",
      ts1,
      "Mig1",
      ["up1"],
      ["down1"],
      migration.MigrationOptions(False),
      "hash1",
    )
  let mig2 =
    migration.Migration(
      "path2",
      ts2,
      "Mig2",
      ["up2"],
      ["down2"],
      migration.MigrationOptions(False),
      "hash2",
    )
  let mig3 =
    migration.Migration(
      "path3",
      ts3,
      "Mig3",
      ["up3"],
      ["down3"],
      migration.MigrationOptions(False),
      "hash3",
    )

  let db_mig1 =
    migration.Migration(
      "",
      ts1,
      "Mig1",
      [],
      [],
      migration.MigrationOptions(False),
      "hash1",
    )
  let db_mig3 =
    migration.Migration(
      "",
      ts3,
      "Mig3",
      [],
      [],
      migration.MigrationOptions(True),
      "hash3",
    )

  let migs_from_files = [mig1, mig2, mig3]
  let migs_from_db = [db_mig1, db_mig3]

  let assert Ok(matches) =
    migration.match_migrations(migs_from_db, migs_from_files, False)

  assert matches == [mig1, mig3]
}

pub fn match_migrations_no_match_test() {
  let assert Ok(ts1) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let assert Ok(ts2) = timestamp.parse_rfc3339("2024-12-17T21:01:00Z")
  let assert Ok(ts3) = timestamp.parse_rfc3339("2024-12-17T21:02:00Z")

  let mig1 =
    migration.Migration(
      "path1",
      ts1,
      "Mig1",
      ["up1"],
      ["down1"],
      migration.MigrationOptions(False),
      "hash1",
    )
  let mig2 =
    migration.Migration(
      "path2",
      ts2,
      "Mig2",
      ["up2"],
      ["down2"],
      migration.MigrationOptions(False),
      "hash2",
    )
  let mig3 =
    migration.Migration(
      "path3",
      ts3,
      "Mig3",
      ["up3"],
      ["down3"],
      migration.MigrationOptions(False),
      "hash3",
    )

  let db_mig1 =
    migration.Migration(
      "",
      ts1,
      "Mig1",
      [],
      [],
      migration.MigrationOptions(False),
      "hash1",
    )
  let db_mig_other =
    migration.Migration(
      "",
      ts3,
      "OtherMigration",
      [],
      [],
      migration.MigrationOptions(False),
      "different_hash",
    )

  let migs_from_files = [mig1, mig2, mig3]
  let migs_from_db = [db_mig1, db_mig_other]

  let assert Error(err) =
    migration.match_migrations(migs_from_db, migs_from_files, False)

  assert err
    == migration.CompoundError([
      migration.MigrationNotFound(db_mig_other |> migration.to_fullname()),
    ])
}

pub fn match_migrations_hash_changed_test() {
  let assert Ok(ts1) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let assert Ok(ts2) = timestamp.parse_rfc3339("2024-12-17T21:01:00Z")
  let assert Ok(ts3) = timestamp.parse_rfc3339("2024-12-17T21:02:00Z")

  let mig1 =
    migration.Migration(
      "path1",
      ts1,
      "Mig1",
      ["up1"],
      ["down1"],
      migration.MigrationOptions(False),
      "hash1",
    )
  let mig2 =
    migration.Migration(
      "path2",
      ts2,
      "Mig2",
      ["up2"],
      ["down2"],
      migration.MigrationOptions(False),
      "hash2",
    )
  let mig3 =
    migration.Migration(
      "path3",
      ts3,
      "Mig3",
      ["up3"],
      ["down3"],
      migration.MigrationOptions(False),
      "hash_changed",
    )

  let db_mig1 =
    migration.Migration(
      "",
      ts1,
      "Mig1",
      [],
      [],
      migration.MigrationOptions(False),
      "hash1",
    )
  let db_mig3 =
    migration.Migration(
      "",
      ts3,
      "Mig3",
      [],
      [],
      migration.MigrationOptions(False),
      "hash3",
    )

  let migs_from_files = [mig1, mig2, mig3]
  let migs_from_db = [db_mig1, db_mig3]

  let assert Error(err) =
    migration.match_migrations(migs_from_db, migs_from_files, False)

  assert err
    == migration.CompoundError([
      migration.FileHashChanged(db_mig3 |> migration.to_fullname()),
    ])
}

pub fn match_migrations_no_hash_check_test() {
  let assert Ok(ts1) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let assert Ok(ts2) = timestamp.parse_rfc3339("2024-12-17T21:01:00Z")
  let assert Ok(ts3) = timestamp.parse_rfc3339("2024-12-17T21:02:00Z")

  let mig1 =
    migration.Migration(
      "path1",
      ts1,
      "Mig1",
      ["up1"],
      ["down1"],
      migration.MigrationOptions(False),
      "hash1",
    )
  let mig2 =
    migration.Migration(
      "path2",
      ts2,
      "Mig2",
      ["up2"],
      ["down2"],
      migration.MigrationOptions(False),
      "hash2",
    )
  let mig3 =
    migration.Migration(
      "path3",
      ts3,
      "Mig3",
      ["up3"],
      ["down3"],
      migration.MigrationOptions(False),
      "hash3",
    )

  let db_mig1 =
    migration.Migration(
      "",
      ts1,
      "Mig1",
      [],
      [],
      migration.MigrationOptions(False),
      "hash456",
    )
  let db_mig3 =
    migration.Migration(
      "",
      ts3,
      "Mig3",
      [],
      [],
      migration.MigrationOptions(False),
      "hash789",
    )

  let migs_from_files = [mig1, mig2, mig3]
  let migs_from_db = [db_mig1, db_mig3]

  let assert Ok(matches) =
    migration.match_migrations(migs_from_db, migs_from_files, True)

  assert matches == [mig1, mig3]
}

pub fn is_zero_migration_test() {
  assert migration.Migration(
      "",
      utils.epoch(),
      "",
      [],
      [],
      migration.MigrationOptions(False),
      "",
    )
    |> migration.is_zero_migration()
    == True
}

pub fn is_not_zero_migration_test() {
  assert migration.Migration(
      "priv/migrations/01011970000000-test.sql",
      utils.epoch(),
      "test",
      ["CREATE TABLE test();"],
      ["DROP TABLE test;"],
      migration.MigrationOptions(False),
      "fde7050fe128b1ccf71703ab7463748a481fc1d347ab17ea3eaee56f4a2cd96f",
    )
    |> migration.is_zero_migration()
    == False

  migration.Migration(
    "",
    timestamp.system_time(),
    "test",
    ["CREATE TABLE test();"],
    ["DROP TABLE test;"],
    migration.MigrationOptions(False),
    "fde7050fe128b1ccf71703ab7463748a481fc1d347ab17ea3eaee56f4a2cd96f",
  )
  |> migration.is_zero_migration()
  == False
}

pub fn create_zero_migration_test() {
  let name = "ZeroMigration"
  let queries_up = ["CREATE TABLE zero_migration();"]
  let queries_down = ["DROP TABLE zero_migration;"]

  let zero_mig = migration.create_zero_migration(name, queries_up, queries_down)

  assert zero_mig.path == ""
  assert zero_mig.name == name
  assert zero_mig.queries_up == queries_up
  assert zero_mig.queries_down == queries_down
  assert string.uppercase(zero_mig.sha256)
    == "FAE7D5FFD35013EB3CE95190A3AD407CF07D0F6F161607E29599A1597EA2891A"

  assert migration.is_zero_migration(zero_mig)
}

pub fn chunk_migrations_test() {
  let mig1 =
    migration.Migration(
      "",
      utils.epoch(),
      "Mig1",
      ["a", "b"],
      ["c", "d"],
      migration.MigrationOptions(False),
      "",
    )
  let mig2 =
    migration.Migration(
      "",
      utils.epoch(),
      "Mig2",
      ["e", "f"],
      ["g", "h"],
      migration.MigrationOptions(False),
      "",
    )
  let mig3 =
    migration.Migration(
      "",
      utils.epoch(),
      "Mig3",
      ["i", "j"],
      ["k", "l"],
      migration.MigrationOptions(True),
      "",
    )
  let mig4 =
    migration.Migration(
      "",
      utils.epoch(),
      "Mig4",
      ["m", "n"],
      ["o", "p"],
      migration.MigrationOptions(False),
      "",
    )

  let chunks = migration.chunk_by_transaction_option([mig1, mig2, mig3, mig4])

  assert chunks
    == [
      #(False, [mig1, mig2]),
      #(True, [mig3]),
      #(False, [mig4]),
    ]
}
