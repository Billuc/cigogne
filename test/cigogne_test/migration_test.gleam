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
  let mig = migration.Migration("", ts, "SetFolder", [], [], "")

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
  let mig = migration.Migration("", ts, "ToFullname", [], [], "")

  assert migration.to_fullname(mig) == "20241217210000-ToFullname"
}

pub fn compare_eq_test() {
  let assert Ok(ts) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let mig1 = migration.Migration("", ts, "CompareEq", [], [], "")
  let mig2 = migration.Migration("", ts, "CompareEq", [], [], "")

  assert migration.compare(mig1, mig2) == order.Eq
}

pub fn compare_lt_timestamp_test() {
  let assert Ok(ts1) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let assert Ok(ts2) = timestamp.parse_rfc3339("2024-12-17T21:01:00Z")
  let mig1 = migration.Migration("", ts1, "CompareLt", [], [], "")
  let mig2 = migration.Migration("", ts2, "CompareLt", [], [], "")

  assert migration.compare(mig1, mig2) == order.Lt
  assert migration.compare(mig2, mig1) == order.Gt
}

pub fn compare_lt_name_test() {
  let assert Ok(ts) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let mig1 = migration.Migration("", ts, "AName", [], [], "")
  let mig2 = migration.Migration("", ts, "BName", [], [], "")

  assert migration.compare(mig1, mig2) == order.Lt
  assert migration.compare(mig2, mig1) == order.Gt
}

pub fn merge_no_migrations_test() {
  let assert Ok(ts) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let assert Error(err) = migration.merge([], ts, "MergeTest")
  assert err == migration.NothingToMergeError
}

pub fn merge_test() {
  let assert Ok(ts1) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let assert Ok(ts2) = timestamp.parse_rfc3339("2024-12-17T21:01:00Z")
  let assert Ok(ts3) = timestamp.parse_rfc3339("2024-12-17T21:02:00Z")
  let assert Ok(ts4) = timestamp.parse_rfc3339("2024-12-17T21:03:00Z")
  let mig1 = migration.Migration("", ts1, "Mig1", ["up1"], ["down1"], "")
  let mig2 = migration.Migration("", ts2, "Mig2", ["up2"], ["down2"], "")
  let mig3 = migration.Migration("", ts3, "Mig3", ["up3"], ["down3"], "")

  let assert Ok(merged) =
    migration.merge([mig1, mig2, mig3], ts4, "MergedMigration")

  assert merged.path == ""
  assert merged.timestamp == ts4
  assert merged.name == "MergedMigration"
  assert merged.queries_up
    == [
      "\n--- " <> migration.to_fullname(mig1),
      "up1",
      "\n--- " <> migration.to_fullname(mig2),
      "up2",
      "\n--- " <> migration.to_fullname(mig3),
      "up3",
    ]
  assert merged.queries_down
    == [
      "\n--- " <> migration.to_fullname(mig3),
      "down3",
      "\n--- " <> migration.to_fullname(mig2),
      "down2",
      "\n--- " <> migration.to_fullname(mig1),
      "down1",
    ]
  assert merged.sha256 == ""
}

pub fn find_non_applied_test() {
  let assert Ok(ts1) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let assert Ok(ts2) = timestamp.parse_rfc3339("2024-12-17T21:01:00Z")
  let assert Ok(ts3) = timestamp.parse_rfc3339("2024-12-17T21:02:00Z")
  let mig1 = migration.Migration("", ts1, "Mig1", ["up1"], ["down1"], "")
  let mig2 = migration.Migration("", ts2, "Mig2", ["up2"], ["down2"], "")
  let mig3 = migration.Migration("", ts3, "Mig3", ["up3"], ["down3"], "")
  let all = [mig1, mig2, mig3]
  let applied = [mig1, mig3]

  let non_applied = migration.find_unapplied(all, applied)

  assert non_applied == [mig2]
}

pub fn find_multiple_non_applied_test() {
  let assert Ok(ts1) = timestamp.parse_rfc3339("2024-12-17T21:00:00Z")
  let assert Ok(ts2) = timestamp.parse_rfc3339("2024-12-17T21:01:00Z")
  let assert Ok(ts3) = timestamp.parse_rfc3339("2024-12-17T21:02:00Z")
  let mig1 = migration.Migration("", ts1, "Mig1", ["up1"], ["down1"], "")
  let mig2 = migration.Migration("", ts2, "Mig2", ["up2"], ["down2"], "")
  let mig3 = migration.Migration("", ts3, "Mig3", ["up3"], ["down3"], "")
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
    migration.Migration("path1", ts1, "Mig1", ["up1"], ["down1"], "hash1")
  let mig2 =
    migration.Migration("path2", ts2, "Mig2", ["up2"], ["down2"], "hash2")
  let mig3 =
    migration.Migration("path3", ts3, "Mig3", ["up3"], ["down3"], "hash3")

  let db_mig1 = migration.Migration("", ts1, "Mig1", [], [], "hash1")
  let db_mig3 = migration.Migration("", ts3, "Mig3", [], [], "hash3")

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
    migration.Migration("path1", ts1, "Mig1", ["up1"], ["down1"], "hash1")
  let mig2 =
    migration.Migration("path2", ts2, "Mig2", ["up2"], ["down2"], "hash2")
  let mig3 =
    migration.Migration("path3", ts3, "Mig3", ["up3"], ["down3"], "hash3")

  let db_mig1 = migration.Migration("", ts1, "Mig1", [], [], "hash1")
  let db_mig_other =
    migration.Migration("", ts3, "OtherMigration", [], [], "different_hash")

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
    migration.Migration("path1", ts1, "Mig1", ["up1"], ["down1"], "hash1")
  let mig2 =
    migration.Migration("path2", ts2, "Mig2", ["up2"], ["down2"], "hash2")
  let mig3 =
    migration.Migration(
      "path3",
      ts3,
      "Mig3",
      ["up3"],
      ["down3"],
      "hash_changed",
    )

  let db_mig1 = migration.Migration("", ts1, "Mig1", [], [], "hash1")
  let db_mig3 = migration.Migration("", ts3, "Mig3", [], [], "hash3")

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
    migration.Migration("path1", ts1, "Mig1", ["up1"], ["down1"], "hash1")
  let mig2 =
    migration.Migration("path2", ts2, "Mig2", ["up2"], ["down2"], "hash2")
  let mig3 =
    migration.Migration("path3", ts3, "Mig3", ["up3"], ["down3"], "hash3")

  let db_mig1 = migration.Migration("", ts1, "Mig1", [], [], "hash456")
  let db_mig3 = migration.Migration("", ts3, "Mig3", [], [], "hash789")

  let migs_from_files = [mig1, mig2, mig3]
  let migs_from_db = [db_mig1, db_mig3]

  let assert Ok(matches) =
    migration.match_migrations(migs_from_db, migs_from_files, True)

  assert matches == [mig1, mig3]
}

pub fn is_zero_migration_test() {
  assert migration.Migration("", utils.epoch(), "", [], [], "")
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
