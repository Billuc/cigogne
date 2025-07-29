import cigogne/internal/utils
import cigogne/types
import gleam/bool
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp

const max_name_length = 255

pub fn format_migration_timestamp(timestamp: timestamp.Timestamp) -> String {
  let #(date, time) = timestamp |> timestamp.to_calendar(calendar.utc_offset)

  let date_str =
    [date.year, date.month |> calendar.month_to_int, date.day]
    |> list.map(int_to_2_chars_string)
    |> string.join("")
  let time_str =
    [time.hours, time.minutes, time.seconds]
    |> list.map(int_to_2_chars_string)
    |> string.join("")

  date_str <> time_str
}

fn int_to_2_chars_string(n: Int) -> String {
  case n {
    n if n < 10 -> "0" <> int.to_string(n)
    _ -> int.to_string(n)
  }
}

pub fn parse_migration_timestamp(
  timestamp_str: String,
) -> Result(timestamp.Timestamp, types.MigrateError) {
  use <- bool.guard(
    string.length(timestamp_str) != 14,
    Error(types.DateParseError(timestamp_str)),
  )

  let year = string.slice(timestamp_str, 0, 4) |> int.parse
  let month = string.slice(timestamp_str, 4, 2) |> int.parse
  let day = string.slice(timestamp_str, 6, 2) |> int.parse
  let hours = string.slice(timestamp_str, 8, 2) |> int.parse
  let minutes = string.slice(timestamp_str, 10, 2) |> int.parse
  let seconds = string.slice(timestamp_str, 12, 2) |> int.parse

  case year, month, day, hours, minutes, seconds {
    Ok(y), Ok(m), Ok(d), Ok(h), Ok(min), Ok(s) -> {
      calendar.month_from_int(m)
      |> result.replace_error(types.DateParseError(timestamp_str))
      |> result.map(fn(m) {
        timestamp.from_calendar(
          calendar.Date(y, m, d),
          calendar.TimeOfDay(h, min, s, 0),
          calendar.utc_offset,
        )
      })
    }
    _, _, _, _, _, _ -> Error(types.DateParseError(timestamp_str))
  }
}

pub fn format_migration_name(migration: types.Migration) -> String {
  format_migration_timestamp(migration.timestamp) <> "-" <> migration.name
}

pub fn to_migration_filename(
  timestamp: timestamp.Timestamp,
  name: String,
) -> String {
  format_migration_timestamp(timestamp) <> "-" <> name <> ".sql"
}

pub fn check_name(name: String) -> Result(String, types.MigrateError) {
  use <- bool.guard(
    string.length(name) > max_name_length,
    Error(types.NameTooLongError(name)),
  )
  Ok(name)
}

pub fn find_migration(
  migrations: List(types.Migration),
  data: types.Migration,
) -> Result(types.Migration, types.MigrateError) {
  migrations
  |> list.find(fn(m) { m.timestamp == data.timestamp && m.name == data.name })
  |> result.replace_error(types.MigrationNotFoundError(
    data.timestamp,
    data.name,
  ))
}

pub fn compare_migrations(
  migration_a: types.Migration,
  migration_b: types.Migration,
) -> order.Order {
  timestamp.compare(migration_a.timestamp, migration_b.timestamp)
  |> order.break_tie(string.compare(migration_a.name, migration_b.name))
}

pub fn find_first_non_applied_migration(
  migrations: List(types.Migration),
  applied_migrations: List(types.Migration),
) -> Result(types.Migration, types.MigrateError) {
  let sorted_migrations = list.sort(migrations, compare_migrations)
  let sorted_applied = list.sort(applied_migrations, compare_migrations)

  case loop_lists_and_find_non_applied(sorted_migrations, sorted_applied) {
    option.None -> Error(types.NoMigrationToApplyError)
    option.Some(mig) -> Ok(mig)
  }
}

fn loop_lists_and_find_non_applied(
  to_apply: List(types.Migration),
  applied: List(types.Migration),
) -> option.Option(types.Migration) {
  case to_apply, applied {
    [], _ -> option.None
    [mig, ..], [] -> option.Some(mig)
    [mig_a, ..rest_a], [mig_b, ..rest_b] -> {
      case compare_migrations(mig_a, mig_b) {
        order.Eq -> loop_lists_and_find_non_applied(rest_a, rest_b)
        order.Gt -> loop_lists_and_find_non_applied(to_apply, rest_b)
        order.Lt -> option.Some(mig_a)
      }
    }
  }
}

pub fn find_all_non_applied_migration(
  migrations: List(types.Migration),
  applied_migrations: List(types.Migration),
) -> Result(List(types.Migration), types.MigrateError) {
  let sorted_migrations = list.sort(migrations, compare_migrations)
  let sorted_applied = list.sort(applied_migrations, compare_migrations)

  case
    loop_lists_and_find_all_non_applied(sorted_migrations, sorted_applied, [])
  {
    [] -> Error(types.NoMigrationToApplyError)
    list_migs -> Ok(list.reverse(list_migs))
  }
}

fn loop_lists_and_find_all_non_applied(
  to_apply: List(types.Migration),
  applied: List(types.Migration),
  found: List(types.Migration),
) -> List(types.Migration) {
  case to_apply, applied {
    [], _ -> found
    [mig, ..rest], [] -> {
      loop_lists_and_find_all_non_applied(rest, applied, [mig, ..found])
    }
    [mig_a, ..rest_a], [mig_b, ..rest_b] -> {
      case compare_migrations(mig_a, mig_b) {
        order.Eq -> loop_lists_and_find_all_non_applied(rest_a, rest_b, found)
        order.Lt ->
          loop_lists_and_find_all_non_applied(rest_a, applied, [mig_a, ..found])
        order.Gt -> loop_lists_and_find_all_non_applied(to_apply, rest_b, found)
      }
    }
  }
}

pub fn find_n_migrations_to_apply(
  migrations: List(types.Migration),
  applied: List(types.Migration),
  count: Int,
) -> Result(List(types.Migration), types.MigrateError) {
  use <- bool.guard(count <= 0, Ok([]))

  let sorted_migrations = list.sort(migrations, compare_migrations)
  let sorted_applied = list.sort(applied, compare_migrations)

  find_n_non_applied(sorted_migrations, sorted_applied, [], count)
  |> result.map(list.reverse)
}

pub fn find_n_migrations_to_rollback(
  migrations: List(types.Migration),
  applied: List(types.Migration),
  count: Int,
) -> Result(List(types.Migration), types.MigrateError) {
  use <- bool.guard(count <= 0, Ok([]))

  let sorted_migrations =
    list.sort(migrations, order.reverse(compare_migrations))
  let sorted_applied = list.sort(applied, order.reverse(compare_migrations))

  find_n_to_rollback(sorted_migrations, sorted_applied, [], count)
  |> result.map(list.reverse)
}

fn find_n_non_applied(
  migrations: List(types.Migration),
  applied: List(types.Migration),
  found: List(types.Migration),
  n: Int,
) -> Result(List(types.Migration), types.MigrateError) {
  case n {
    0 -> Ok(found)
    _ ->
      case migrations, applied {
        [], _ -> Ok(found)
        [mig_a, ..rest_a], [mig_b, ..rest_b] -> {
          case compare_migrations(mig_a, mig_b) {
            order.Eq -> find_n_non_applied(rest_a, rest_b, found, n)
            order.Lt ->
              find_n_non_applied(rest_a, applied, [mig_a, ..found], n - 1)
            order.Gt -> find_n_non_applied(migrations, rest_b, found, n)
          }
        }
        [mig, ..rest], [] ->
          find_n_non_applied(rest, applied, [mig, ..found], n - 1)
      }
  }
}

fn find_n_to_rollback(
  migrations: List(types.Migration),
  applied: List(types.Migration),
  found: List(types.Migration),
  n: Int,
) -> Result(List(types.Migration), types.MigrateError) {
  case n {
    0 -> Ok(found)
    _ ->
      case applied, migrations {
        [], _ -> Ok(found)
        [mig_a, ..rest_a], [mig_b, ..rest_b] -> {
          case compare_migrations(mig_a, mig_b) {
            order.Eq ->
              find_n_to_rollback(rest_a, rest_b, [mig_b, ..found], n - 1)
            order.Gt ->
              Error(types.MigrationNotFoundError(mig_a.timestamp, mig_a.name))
            order.Lt -> find_n_to_rollback(applied, rest_b, found, n)
          }
        }
        [mig, ..rest], [] ->
          find_n_to_rollback(rest, migrations, [mig, ..found], n - 1)
      }
  }
}

/// Create a "zero" migration that should be applied before the user's migrations
pub fn create_zero_migration(
  name: String,
  queries_up: List(String),
  queries_down: List(String),
) -> types.Migration {
  types.Migration(
    "",
    utils.epoch(),
    name,
    queries_up,
    queries_down,
    utils.make_sha256(
      queries_up |> string.join(";") <> queries_down |> string.join(";"),
    ),
  )
}

/// Checks if a migration is a zero migration (has been created with create_zero_migration)
pub fn is_zero_migration(migration: types.Migration) -> Bool {
  migration.path == "" && migration.timestamp == utils.epoch()
}
