import cigogne/internal/database
import cigogne/internal/fs
import cigogne/internal/migrations
import cigogne/internal/utils
import cigogne/types
import gleam/bool
import gleam/dynamic/decode
import gleam/io
import gleam/list
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
  connection: pog.Connection,
) -> Result(Bool, types.MigrateError) {
  pog.query(get_migrations_table_columns_query)
  |> pog.returning(decode.at([0], decode.string))
  |> database.execute(connection)
  |> result.map(list.any(_, fn(col) { col == hash_column_name }))
}

pub fn to_v3(connection: pog.Connection) -> Result(Nil, types.MigrateError) {
  use is_applied <- result.try(is_v3_applied(connection))
  io.println("Is v3 already applied ? " <> is_applied |> bool.to_string)
  use <- bool.guard(is_applied, Ok(Nil))

  use _ <- result.try(create_hash_column(connection))

  use migration_files <- result.try(fs.get_migrations())
  use applied_migrations <- result.try(migrations.get_applied_migrations(
    connection,
  ))

  applied_migrations
  |> list.try_each(set_hash(_, migration_files, connection))
  |> result.map(fn(_) { io.println("All migrations have their hashes set !") })
  |> result.then(fn(_) { set_hash_not_null(connection) })
}

fn create_hash_column(connection: pog.Connection) {
  pog.query(add_hash_column_migration)
  |> database.execute(connection)
  |> result.map(fn(_) { io.println("Sha256 column created") })
}

fn set_hash_not_null(connection: pog.Connection) {
  pog.query(drop_hash_default_migration)
  |> database.execute(connection)
  |> result.map(fn(_) { io.println("Sha256 column default dropped") })
}

fn set_hash(
  applied_mig: types.Migration,
  files: List(types.Migration),
  connection: pog.Connection,
) -> Result(Nil, types.MigrateError) {
  use <- bool.guard(applied_mig.sha256 != "", Ok(Nil))

  migrations.find_migration(files, applied_mig)
  |> result.then(fn(file) {
    set_hash_migration
    |> pog.query()
    |> pog.parameter(pog.text(file.sha256))
    |> pog.parameter(pog.text(file.name))
    |> pog.parameter(pog.timestamp(
      file.timestamp |> utils.tempo_to_pog_timestamp,
    ))
    |> database.execute(connection)
    |> result.map(fn(_) {
      io.println(
        "Hash set for migration "
        <> fs.to_migration_filename(applied_mig.timestamp, applied_mig.name),
      )
    })
  })
}

pub fn main() {
  use url <- result.try(database.get_url())
  use db_conn <- result.try(database.connect(url))
  io.println("Connected to database at URL " <> url)

  case to_v3(db_conn) {
    Ok(_) -> io.println("Good to go !")
    Error(err) -> types.print_migrate_error(err)
  }
  |> Ok
}
