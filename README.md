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

To use `cigogne`, you first have to create your migration scripts in the `priv/migrations` folder.
Cigogne will look for `.sql` files in this folder to get your migrations.

> Use the `gleam run -m cigogne new NAME` command to create a new migration

Cigogne expects 
the sql files to have the following format `<MigrationTimestamp>-<MigrationName>.sql`. This way we 
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
# Apply/roll back N migrations (apply if N > 0, roll back otherwise)
gleam run -m cigogne apply N
# Show the last applied migration and the current DB schema
gleam run -m cigogne show
# Create a new migration with name NAME
gleam run -m cigogne new NAME
```

You can also use it in your server initalisation function to make sure your schema is up-to-date with your code.

```gleam
import cigogne

pub fn init() -> Nil {
    use db_connection <- db_connect() // to be implemented
    cigogne.execute_migrations_to_last(db_connection)
    |> result.then(cigogne.update_schema_file(db_url))
    |> result.map_error(cigogne.print_error)
    |> result.unwrap_both

    // Or directly by using environment variables
    cigogne.migrate_to_last()
    |> result.map_error(cigogne.print_error)
    |> result.unwrap_both
}
```

> By default, `cigogne` gets the database url from the `DATABASE_URL` environment variable.  
> Also, the migrate_up, _down, _n, and _to_last functions systematically update a schema file
> whenever they are successful.

Further documentation can be found at <https://hexdocs.pm/cigogne>.

## Hashes

A hash of the migration file is saved to the database when a migration is applied. This way, we can ensure that migrations are not modified after being applied. If a migration has been modified, you will get an error as it probably means that you should reset your database to update a migration.

> This feature was introduced in version 3 of cigogne.
> Note that it requires Gleam >=1.9.0. 
> If you use earlier versions of the library, you can use the to_v3 script to have them filled automatically.  
> 
> Command: `gleam run -m cigogne/to_v3`

## Development ideas

I have a few ideas to improve this library that I may implement in the future.  
Let me know if some of those are of interest to you and I will prioritize them.

- Specify default schema (for schema file) via an envvar.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
