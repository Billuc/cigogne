# 🪽 cigogne - Easy migrations in Gleam

[![Package Version](https://img.shields.io/hexpm/v/cigogne)](https://hex.pm/packages/cigogne)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/cigogne/)

Cigogne (French for stork) is a simple tool to manage migrations for your Postgres database.
The idea is that instead of writing schemas in Gleam and having a tool do the migration scripts for you,
with Cigogne you have total control on your migrations. That approach gives you more freedom on how you want to do
your migrations for the price of a bit of time and learning some database skills.

For example, if you decide to rename a column, you can use a `ALTER TABLE RENAME COLUMN` query.  
If you decide to change a column's data type, you can decide how to populate it based on the old values.

As a plus, this integrates really well with the approach provided by [squirrel](https://hexdocs.pm/squirrel/).

## Installation

```sh
gleam add --dev cigogne
```

Cigogne can also be installed as a regular dependency and used in your project. See documentation about the `cigogne` module to know more.

## Usage

To use `cigogne`, you first have to create your migration scripts in a folder (by default `priv/migrations`).
Cigogne will look for `.sql` files in this folder to get your migrations.

> Use the `gleam run -m cigogne new --name NAME` command to create a new migration

Cigogne expects the sql files to have the following format `<MigrationTimestamp>-<MigrationName>.sql`. This way we
can get an order in which migrations should be applied and a descriptive name right away. It also
allows for easy sorting of your migration scripts and forces you to give it a meaningful name.

You can then write your migration scripts. It should look like this:

```sql
--- migration:up
CREATE TABLE users(
    id UUID PRIMARY KEY,
    firstName TEXT NOT NULL,
    age INT NOT NULL
);

--- migration:down
DROP TABLE users;

--- migration:end
```

The `--- migration:` comments are used to separate between the queries used for the "up migration" and the "down migration".

You are now ready to execute your migration ! The first way of executing your migration is via the command line :

```sh
# Apply the next migration
gleam run -m cigogne up
# Roll back the last applied migration
gleam run -m cigogne down
# Apply all migrations not yet applied
gleam run -m cigogne last
# Show the last applied migration and the current DB schema
gleam run -m cigogne show
# Create a new migration with name NAME
gleam run -m cigogne new --name NAME
```

The first 4 actions have flags that allow you to specify where to get the migration files, how to connect to the database, etc.

> Run `gleam run -m cigogne help` to get a list of all actions and `gleam run -m cigogne help <action>` to get details of all the available flags

You can also use cigogne in your server initalisation function to make sure your database is up-to-date.

```gleam
import cigogne
import cigogne/types

pub fn init() -> Nil {
  let config = cigogne.default_config
  // Configure cigogne using this config object. Example:
  // let config = types.Config(
  //   ..cigogne.default_config,
  //   connection: types.UrlConfig("postgres://my_user@192.168.0.101:5433/my_db")
  // )

  use engine <- result.try(cigogne.create_engine(config))
  cigogne.apply_to_last(engine)
}
```

> By default, `cigogne` gets the database url from the `DATABASE_URL` environment variable.  
> Also, by default, the apply, rollback, apply_n, rollback_n and apply_to_last functions update a schema file
> whenever they are successful.  
> See the cigogne.default_config constant for more information.

Further documentation can be found at <https://hexdocs.pm/cigogne>.

## Hashes

A hash of the migration file is saved to the database when a migration is applied. This way, we can ensure that migrations are not modified after being applied. If a migration has been modified, you will get an error as it probably means that you should reset your database to update a migration.

> This feature was introduced in version 3 of cigogne.
> Note that it requires Gleam >=1.9.0.
> If you use earlier versions of the library, you can use the to_v3 script to have them filled automatically.
>
> Command: `gleam run -m cigogne/to_v3`

## Development ideas

If you have feature requests or ideas of improvments, don't hesitate to open an issue.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
