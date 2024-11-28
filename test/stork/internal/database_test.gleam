import envoy
import gleeunit/should
import cigogne/internal/database
import cigogne/types

pub fn get_url_from_envvar_test() {
  envoy.set(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/postgres",
  )

  database.get_url()
  |> should.be_ok()
  |> should.equal("postgresql://postgres:postgres@localhost:5432/postgres")
}

pub fn get_url_fails_if_envvar_not_set_test() {
  envoy.unset("DATABASE_URL")

  database.get_url()
  |> should.be_error()
  |> should.equal(types.EnvVarError("DATABASE_URL"))
}
