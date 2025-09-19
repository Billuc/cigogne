import cigogne
import cigogne/config
import cigogne/internal/database
import cigogne/migration
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

fn is_v3_applied(
  db_data: database.DatabaseData,
) -> Result(Bool, cigogne.CigogneError) {
  pog.query(get_migrations_table_columns_query)
  |> pog.returning(decode.at([0], decode.string))
  |> pog.execute(db_data.connection)
  |> result.map_error(database.PogQueryError)
  |> result.map_error(cigogne.DatabaseError)
  |> result.map(fn(res) {
    list.any(res.rows, fn(col) { col == hash_column_name })
  })
}

fn to_v3(
  db_data: database.DatabaseData,
  app_name: String,
) -> Result(Nil, cigogne.CigogneError) {
  use is_applied <- result.try(is_v3_applied(db_data))
  io.println("Is v3 already applied ? " <> is_applied |> bool.to_string)
  use <- bool.guard(is_applied, Ok(Nil))

  use _ <- result.try(create_hash_column(db_data.connection))

  use migration_files <- result.try(cigogne.read_migrations(
    config.Config(
      ..config.default_config,
      migrations: config.MigrationsConfig(
        app_name,
        option.Some("migrations"),
        [],
      ),
    ),
  ))
  use applied_migrations <- result.try(
    database.get_applied_migrations(db_data)
    |> result.map_error(cigogne.DatabaseError),
  )
  use applied_migrations <- result.try(
    migration.match_migrations(applied_migrations, migration_files)
    |> result.map_error(cigogne.MigrationError),
  )

  applied_migrations
  |> list.try_each(set_hash(_, db_data.connection))
  |> result.map(fn(_) { io.println("All migrations have their hashes set !") })
  |> result.try(fn(_) { set_hash_not_null(db_data.connection) })
}

fn create_hash_column(
  connection: pog.Connection,
) -> Result(Nil, cigogne.CigogneError) {
  pog.query(add_hash_column_migration)
  |> pog.execute(connection)
  |> result.map_error(database.PogQueryError)
  |> result.map_error(cigogne.DatabaseError)
  |> result.map(fn(_) { io.println("Sha256 column created") })
}

fn set_hash_not_null(
  connection: pog.Connection,
) -> Result(Nil, cigogne.CigogneError) {
  pog.query(drop_hash_default_migration)
  |> pog.execute(connection)
  |> result.map_error(database.PogQueryError)
  |> result.map_error(cigogne.DatabaseError)
  |> result.map(fn(_) { io.println("Sha256 column default dropped") })
}

fn set_hash(
  applied_mig: migration.Migration,
  connection: pog.Connection,
) -> Result(Nil, cigogne.CigogneError) {
  use <- bool.guard(migration.is_zero_migration(applied_mig), Ok(Nil))

  set_hash_migration
  |> pog.query()
  |> pog.parameter(pog.text(applied_mig.sha256))
  |> pog.parameter(pog.text(applied_mig.name))
  |> pog.parameter(pog.timestamp(applied_mig.timestamp))
  |> pog.execute(connection)
  |> result.map_error(database.PogQueryError)
  |> result.map_error(cigogne.DatabaseError)
  |> result.map(fn(_) {
    io.println("Hash set for migration " <> migration.to_fullname(applied_mig))
  })
}

/// Entry point for the migration to v3 from v1 or v2.
/// v3 introduces a sha256 column in the _migrations table to ensure
/// the integrity of applied migrations.
/// This script will add the column, compute the hash for each applied migration
/// and set it in the database.
///
/// Usage: `gleam run -m cigogne/to_v3`
pub fn main() {
  let assert Ok(app_name) = config.get_app_name()
  let config =
    config.Config(
      config.EnvVarConfig,
      config.MigrationTableConfig(
        option.Some("public"),
        option.Some("migrations"),
      ),
      config.MigrationsConfig(app_name, option.Some("migrations"), []),
    )
  let assert Ok(db_data) = database.init(config)
  io.println("Connected to database")

  case to_v3(db_data, app_name) {
    Ok(_) -> io.println("Good to go !")
    Error(err) -> cigogne.print_error(err)
  }
}
