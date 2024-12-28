import cigogne/internal/utils
import cigogne/types
import envoy
import gleam/result
import pog
import shellout

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
  queries: List(pog.Query(_)),
  ignore_errors: Bool,
) -> Result(Nil, types.MigrateError) {
  use transaction <- transaction(connection)
  handle_queries(transaction, queries, ignore_errors)
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
  queries: List(pog.Query(_)),
  ignore_errors: Bool,
) -> Result(Nil, String) {
  let result = exec_queries(conn, queries)

  case ignore_errors, result {
    True, Error(pog.ConstraintViolated(_, "_migrations_pkey", _)) -> Ok(Nil)
    _, _ -> result |> result.map_error(utils.describe_query_error)
  }
}

fn exec_queries(
  conn: pog.Connection,
  queries: List(pog.Query(_)),
) -> Result(Nil, pog.QueryError) {
  case queries {
    [] -> Ok(Nil)
    [q, ..rest] -> {
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
