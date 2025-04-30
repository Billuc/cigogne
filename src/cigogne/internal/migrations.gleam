import cigogne/internal/utils
import cigogne/types
import gleam/bool
import gleam/dynamic/decode
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/string
import pog
import tempo/naive_datetime

const query_applied_migrations = "SELECT createdAt, name, sha256 FROM _migrations ORDER BY appliedAt ASC;"

pub fn get_applied_migrations(
  conn: pog.Connection,
) -> Result(List(types.Migration), types.MigrateError) {
  pog.query(query_applied_migrations)
  |> pog.returning({
    use timestamp <- decode.field(0, pog.timestamp_decoder())
    use name <- decode.field(1, decode.string)
    use hash <- decode.field(2, decode.string)
    decode.success(#(timestamp, name, hash))
  })
  |> pog.execute(conn)
  |> result.map_error(types.PGOQueryError)
  |> result.then(fn(returned) {
    case returned {
      pog.Returned(0, _) | pog.Returned(_, []) -> Error(types.NoResultError)
      pog.Returned(_, applied) ->
        applied
        |> list.try_map(fn(data) {
          utils.pog_to_tempo_timestamp(data.0)
          |> result.map(fn(timestamp) {
            types.Migration("", timestamp, data.1, [], [], data.2)
          })
          |> result.replace_error(
            types.DateParseError(utils.pog_timestamp_to_string(data.0)),
          )
        })
    }
  })
}

pub fn find_migration(
  migrations: List(types.Migration),
  data: types.Migration,
) -> Result(types.Migration, types.MigrateError) {
  migrations
  |> list.find(fn(m) {
    naive_datetime.is_equal(m.timestamp, data.timestamp) && m.name == data.name
  })
  |> result.replace_error(types.MigrationNotFoundError(
    data.timestamp,
    data.name,
  ))
}

pub fn compare_migrations(
  migration_a: types.Migration,
  migration_b: types.Migration,
) -> order.Order {
  naive_datetime.compare(migration_a.timestamp, migration_b.timestamp)
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
  case count {
    n if n > 0 -> {
      let sorted_migrations = list.sort(migrations, compare_migrations)
      let sorted_applied = list.sort(applied, compare_migrations)
      find_n_non_applied(sorted_migrations, sorted_applied, [], n)
    }
    n if n < 0 -> {
      let sorted_migrations =
        list.sort(migrations, order.reverse(compare_migrations))
      let sorted_applied = list.sort(applied, order.reverse(compare_migrations))
      find_n_to_rollback(sorted_migrations, sorted_applied, [], -n)
    }
    _ -> Ok([])
  }
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

/// Checks if a migration is a zero migration (has been created with create_zero_migration)
pub fn is_zero_migration(migration: types.Migration) -> Bool {
  { migration.path == "" }
  |> bool.and(naive_datetime.is_equal(migration.timestamp, utils.tempo_epoch()))
}
