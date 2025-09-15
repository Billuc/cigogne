# 🪽 cigogne - Easy migrations in Gleam

[![Package Version](https://img.shields.io/hexpm/v/cigogne)](https://hex.pm/packages/cigogne)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/cigogne/)

Cigogne (French for stork) is a simple tool to manage migrations for your Postgres database.
The idea is that you have total control on your migrations, since you will be writing SQL files directly.
That approach gives you more freedom on how you want to do your migrations for the price of a bit of time and learning some database skills.

For example, if you decide to rename a column, you can use a `ALTER TABLE RENAME COLUMN` query !  
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
can get the order in which migrations should be applied and a descriptive name right away. It also
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

The `--- migration:` comments are used to separate between the queries used for the "up migration" (used when you apply the migration)
and the "down migration" (used when you rollback the migration).

You are now ready to execute your migration ! The first way of executing your migration is via the command line :

```sh
# Apply the next migration
gleam run -m cigogne up
# Roll back the last applied migration
gleam run -m cigogne down
# Apply all migrations not yet applied
gleam run -m cigogne up-all
# Show the applied migration
gleam run -m cigogne show
# Create a new migration with name NAME
gleam run -m cigogne new --name NAME
```

> Run `gleam run -m cigogne help` to get a list of all actions and `gleam run -m cigogne help <action>` to get details of all the available flags

You can also use cigogne in your server initalisation function to make sure your database is up-to-date.

```gleam
import cigogne
import cigogne/config

pub fn init() -> Nil {
  use config <- result.try(config.get("my-app"))
  // Configure cigogne using a custom config object. Example:
  // let config = config.Config(
  //   ..config.default_config,
  //   database: config.UrlDbConfig("postgres://my_user@192.168.0.101:5433/my_db")
  // )

  use engine <- result.try(cigogne.create_engine(config))
  cigogne.apply_all(engine)
}
```

Further documentation can be found at <https://hexdocs.pm/cigogne>.

## Libraries

Cigogne can also be used to get and apply migrations from your dependencies, if they use cigogne.

This is done via the `include-lib` action like so: `gleam run -m cigogne include-lib --lib-name my_lib`.

This action merges all the library's migration in a new migration file in your project.  
If you update the library and there are new migrations to include, simply run the command again and the remaining migrations will be included in a new file.

You can also "remove" a lib by using the `remove-lib` command. It does not remove the migrations that were created, but
combines all migrations created by `include-lib` for the specified library and intervert the "up" and "down" migrations.

## Configuration

Most of the cigogne commands can be configured to specify how you want to connect to the database, what table to use to store migration data or in which folder to get the migrations.  
You can get more information on these flags by running `gleam run -m cigogne help <command>`.

To avoid writing a bunch of flags each time you want to run a cigogne command, you can also create a `cigogne.toml` file in your priv directory.  
The easiest way to do it is by using this command: `gleam run -m cigogne update-config`, which will create a the file and write the default config in it.

As its name implies, you can also also use it to update an existing `cigogne.toml` file by passing the same flags as for the others commands.  
However the command rewrite the configuration file, so create a backup if you added valuable information in it !

For reference, here is the default configuration file:

```toml
# This section will be overridden by eventual users of the library
[database]
# If url is defined, it is used to connect to the database
# url = ""

# If other data in this section is defined, it is used to connect
# Otherwise, we fallback to the DATABASE_URL environment variable
# host = "localhost"
# user = "postgres"
# # /!\ It is not recommended to have your password there
# password = "postgres"
# port = 5432
# name = "postgres"

# This section will be overridden by eventual users of the library
[migration-table]
# schema = "public"
# table = "_migrations"

[migrations]
# migration_folder = "migrations"

[migrations.dependencies]
```

## Hashes

A hash of the migration file is saved to the database when a migration is applied. This way, we can ensure that migrations are not modified after being applied.
If a migration has been modified, you will get an error as it probably means that you should reset your database to update a migration.

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
