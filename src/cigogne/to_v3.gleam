import cigogne/internal/database
import cigogne/internal/fs
import cigogne/internal/migrations
import cigogne/internal/utils
import cigogne/types
import gleam/bool
import gleam/dynamic/decode
import gleam/list
import gleam/result
import pog

const get_migrations_table_columns_query = "
  SELECT column_name FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = '_migrations';
"

const hash_column_name = "sha256"

const to_v3_migration = "ALTER TABLE _migrations ADD COLUMN sha256 VARCHAR(64) NOT NULL;"

const set_hash_migration = "UPDATE _migrations SET sha256 = $1 WHERE name = $2 AND createdAt = $3;"

pub fn is_v3_applied(
  connection: pog.Connection,
) -> Result(Bool, types.MigrateError) {
  pog.query(get_migrations_table_columns_query)
  |> pog.returning(decode.string)
  |> database.execute(connection)
  |> result.map(list.any(_, fn(col) { col == hash_column_name }))
}

pub fn to_v3(connection: pog.Connection) -> Result(Nil, types.MigrateError) {
  use is_applied <- result.try(is_v3_applied(connection))
  use <- bool.guard(is_applied, Ok(Nil))

  use _ <- result.try(
    pog.query(to_v3_migration) |> database.execute(connection),
  )
  use migration_files <- result.try(fs.get_migrations())
  use applied_migrations <- result.try(migrations.get_applied_migrations(
    connection,
  ))

  applied_migrations |> list.try_each(set_hash(_, migration_files, connection))
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
    |> result.map(fn(_) { Nil })
  })
}

pub fn main() {
  use url <- result.try(database.get_url())
  use db_conn <- result.try(database.connect(url))
  to_v3(db_conn)
}
