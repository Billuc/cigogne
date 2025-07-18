import cigogne/internal/database
import cigogne/internal/fs
import cigogne/internal/migrations_utils
import cigogne/internal/utils
import cigogne/types
import gleam/bool
import gleam/dynamic/decode
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import pog

const get_migrations_table_columns_query = "
  SELECT column_name FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = '_migrations';
"

const hash_column_name = "sha256"

const add_hash_column_migration = "ALTER TABLE _migrations ADD COLUMN sha256 VARCHAR(64) NOT NULL DEFAULT '';"

const set_hash_migration = "UPDATE _migrations SET sha256 = $1 WHERE name = $2 AND createdAt = $3;"

const drop_hash_default_migration = "ALTER TABLE _migrations ALTER COLUMN sha256 DROP DEFAULT;"

pub fn is_v3_applied(
  db_data: database.DatabaseData,
) -> Result(Bool, types.MigrateError) {
  pog.query(get_migrations_table_columns_query)
  |> pog.returning(decode.at([0], decode.string))
  |> pog.execute(db_data.connection)
  |> result.map_error(types.PGOQueryError)
  |> result.map(fn(res) {
    list.any(res.rows, fn(col) { col == hash_column_name })
  })
}

pub fn to_v3(db_data: database.DatabaseData) -> Result(Nil, types.MigrateError) {
  use is_applied <- result.try(is_v3_applied(db_data))
  io.println("Is v3 already applied ? " <> is_applied |> bool.to_string)
  use <- bool.guard(is_applied, Ok(Nil))

  use _ <- result.try(create_hash_column(db_data.connection))

  use migration_files <- result.try(fs.get_migrations(
    "priv/migrations",
    "*.sql",
  ))
  use applied_migrations <- result.try(database.get_applied_migrations(db_data))

  applied_migrations
  |> list.try_each(set_hash(_, migration_files, db_data.connection))
  |> result.map(fn(_) { io.println("All migrations have their hashes set !") })
  |> result.try(fn(_) { set_hash_not_null(db_data.connection) })
}

fn create_hash_column(
  connection: pog.Connection,
) -> Result(Nil, types.MigrateError) {
  pog.query(add_hash_column_migration)
  |> pog.execute(connection)
  |> result.map_error(types.PGOQueryError)
  |> result.map(fn(_) { io.println("Sha256 column created") })
}

fn set_hash_not_null(
  connection: pog.Connection,
) -> Result(Nil, types.MigrateError) {
  pog.query(drop_hash_default_migration)
  |> pog.execute(connection)
  |> result.map_error(types.PGOQueryError)
  |> result.map(fn(_) { io.println("Sha256 column default dropped") })
}

fn set_hash(
  applied_mig: types.Migration,
  files: List(types.Migration),
  connection: pog.Connection,
) -> Result(Nil, types.MigrateError) {
  use <- bool.guard(applied_mig.sha256 != "", Ok(Nil))
  use <- bool.guard(migrations_utils.is_zero_migration(applied_mig), Ok(Nil))

  migrations_utils.find_migration(files, applied_mig)
  |> result.try(fn(file) {
    set_hash_migration
    |> pog.query()
    |> pog.parameter(pog.text(file.sha256))
    |> pog.parameter(pog.text(file.name))
    |> pog.parameter(pog.timestamp(
      file.timestamp |> utils.tempo_to_pog_timestamp,
    ))
    |> pog.execute(connection)
    |> result.map_error(types.PGOQueryError)
    |> result.map(fn(_) {
      io.println(
        "Hash set for migration "
        <> migrations_utils.to_migration_filename(
          applied_mig.timestamp,
          applied_mig.name,
        ),
      )
    })
  })
}

pub fn main() {
  use db_data <- result.try(database.init(
    types.EnvVarConfig,
    "public",
    "_migrations",
  ))
  io.println(
    "Connected to database at URL " <> db_data.db_url |> option.unwrap("None"),
  )

  case to_v3(db_data) {
    Ok(_) -> io.println("Good to go !")
    Error(err) -> types.print_migrate_error(err)
  }
  |> Ok
}
