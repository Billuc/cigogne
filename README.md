# 🪽 stork - Easy migrations in Gleam

[![Package Version](https://img.shields.io/hexpm/v/stork)](https://hex.pm/packages/stork)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/stork/)

Stork is a simple tool to manage migrations for your Postgres database.
The idea is that instead of writing schemas in Gleam and having a tool do the migration scripts for you,
with Stork you have total control on your migrations. That approach gives you more freedom on how you want to do
your migrations for the price of a bit of time and learning some database skills.

For example, if you decide to rename a column, you can use a `ALTER TABLE RENAME COLUMN` query.  
If you decide to change a column's data type, you can decide how to populate it based on the old values.

As a plus, this integrates really well with the approach provided by [squirrel](https://hexdocs.pm/squirrel/).

## Installation

```sh
gleam add --dev stork
```

Stork can also be installed as a regular dependency and used in your project. See documentation about the `stork` module to know more.

## Usage

To use `stork`, you first have to create your migration scripts in a `migrations` folder.
Stork will look for `.sql` files in these folders to get your migrations. Stork expects 
the sql files to have the following format `<MigrationNumber>-<MigrationName>.sql`. This way we 
can get an order in which migrations should be applied and a descriptive name right away. It also
allows for easy sorting of your migration scripts and forces you to give it a meaningful name.

> This may not be great for everyone, so it may change in the future, maybe to some kind of front matter or something else.  
> Please let me know what you think 😉

You can then write your migration scripts. It should look like this 

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

> Again this may change if we find a better way of doing it !

You are now ready to execute your migration ! The first way of executing your migration is via the command line :

```sh
# Apply the next migration
gleam run -m stork up
# Roll back the last applied migration
gleam run -m stork down
# Apply all migrations not yet applied
gleam run -m stork last
# Apply/roll back migrations until migration N is reached
gleam run -m stork to N
# Show the last applied migration and the current DB schema
gleam run -m stork show
```

You can also use it in your server initalisation function to make sure your schema is up-to-date with your code.

```gleam
import stork

pub fn init() -> Nil {
    let db_url <- get_db_url_from_env() // For example
    let db_connection <- db_connect(db_url)
    stork.execute_migrations_to_last(db_connection)
    |> result.then(stock.update_schema_file(db_url))
    |> result.map_error(stork.print_error)
    |> result.unwrap_both

    // Or directly
    stork.migrate_to_last()
    |> result.map_error(stork.print_error)
    |> result.unwrap_both
}
```

> By default, `stork` gets the database url from the `DATABASE_URL` environment variable.  
> Also, the migrate_up, _down, _to, and _to_last functions systematically update a schema file
> whenever they are successful.

Further documentation can be found at <https://hexdocs.pm/stork>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
