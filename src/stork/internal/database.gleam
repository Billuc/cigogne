import envoy
import gleam/io
import gleam/list
import gleam/result
import pog
import shellout
import stork/types

pub fn get_url() -> Result(String, types.MigrateError) {
  envoy.get("DATABASE_URL")
  |> result.replace_error(types.EnvVarError("DATABASE_URL"))
}

pub fn connect(url: String) -> Result(pog.Connection, types.MigrateError) {
  use config <- result.try(get_config(url))
  config |> pog.connect |> Ok
}

fn get_config(url: String) -> Result(pog.Config, types.MigrateError) {
  pog.url_config(url)
  |> result.replace_error(types.UrlError(url))
}

pub fn execute_batch(
  connection: pog.Connection,
  migration_number: Int,
  queries: List(pog.Query(_)),
) -> Result(Nil, types.MigrateError) {
  use transaction <- transaction(connection)
  handle_queries(transaction, migration_number, queries)
}

fn transaction(
  connection: pog.Connection,
  callback: fn(pog.Connection) -> Result(Nil, String),
) -> Result(Nil, types.MigrateError) {
  pog.transaction(connection, fn(transaction) { callback(transaction) })
  |> result.map_error(types.PGOTransactionError)
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
      // io.println("Executing query : " <> q.sql)
      // io.print(" with values ")
      // io.debug(list.reverse(q.parameters))
      // io.println("")

      let res = q |> pog.execute(conn)
      case res {
        Error(err) -> Error(err)
        Ok(_) -> exec_queries(conn, rest)
      }
    }
  }
}

pub fn get_schema(url: String) -> Result(String, types.MigrateError) {
  shellout.command("psql", [url, "-c", "\\d public.*"], ".", [])
  |> result.map_error(fn(err) { types.SchemaQueryError(err.1) })
}
