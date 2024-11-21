import gleam/int
import gleam/io
import gleam/list
import gleam/result
import pog
import shellout
import stork/types

const query_insert_migration = "INSERT INTO _migrations
VALUES ($1, $2);"

const query_drop_migration = "DELETE FROM _migrations WHERE id = $1;"

pub fn exec_migration_up(
  conn: pog.Connection,
  migration: types.Migration,
) -> Result(Nil, pog.TransactionError) {
  io.println(
    "\nApplying migration "
    <> int.to_string(migration.number)
    <> "-"
    <> migration.name
    <> "\n",
  )
  use conn <- pog.transaction(conn)

  let queries =
    list.map(migration.queries_up, pog.query)
    |> list.append([
      pog.query(query_insert_migration)
      |> pog.parameter(pog.int(migration.number))
      |> pog.parameter(pog.text(migration.name)),
    ])

  handle_queries(conn, migration.number, queries)
}

pub fn exec_migration_down(
  conn: pog.Connection,
  migration: types.Migration,
) -> Result(Nil, pog.TransactionError) {
  io.println(
    "\nRolling back migration "
    <> int.to_string(migration.number)
    <> "-"
    <> migration.name
    <> "\n",
  )
  use conn <- pog.transaction(conn)

  let queries =
    list.map(migration.queries_down, pog.query)
    |> list.append([
      pog.query(query_drop_migration)
      |> pog.parameter(pog.int(migration.number)),
    ])

  handle_queries(conn, migration.number, queries)
}

fn handle_queries(
  conn: pog.Connection,
  migration_number: Int,
  queries: List(pog.Query(_)),
) -> Result(Nil, String) {
  let result = exec_queries(conn, queries)

  case migration_number, result {
    0, Error(pog.ConstraintViolated(_, "_migrations_pkey", _)) -> Ok(Nil)
    _, _ -> result |> result.map_error(types.describe_query_error)
  }
}

fn exec_queries(
  conn: pog.Connection,
  queries: List(pog.Query(_)),
) -> Result(Nil, pog.QueryError) {
  case queries {
    [] -> Ok(Nil)
    [q, ..rest] -> {
      io.println("Executing query : " <> q.sql)
      io.print(" with values ")
      io.debug(list.reverse(q.parameters))
      io.println("")

      let res = q |> pog.execute(conn)
      case res {
        Error(err) -> Error(err)
        Ok(_) -> exec_queries(conn, rest)
      }
    }
  }
}

pub fn get_schema(url: String) -> Result(String, String) {
  shellout.command("psql", [url, "-c", "\\d public.*"], ".", [])
  |> result.map_error(fn(err) { err.1 })
}
