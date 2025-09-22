# CHANGELOG

## 5.0.0 - 22/09/2025

**Breaking changes**

- Many many changes to the API
- Removed schema file generation (use pg_dump instead)

**Features**

- Configuration file support
- Library inclusion support
- Print unapplied migrations action
- Improved messages logged to the console

**Notes**

- Added many tests and doc comments
- Cleaned / reorganized the project to better separate modules, avoid the 'types' module and remove useless code

## 4.0.2 - 02/08/2025

**Fixes**

- Brought back the environment variable method as the default way to connect to the DB

## 4.0.1 - 29/07/2025

**Breaking changes**

- Renamed some functions

## 4.0.0 - 29/07/2025

**Breaking changes**

- Added more configuration options
- Added a new CLI engine
- Dropped gtempo in favor of gleam_time

**Features**

- Upgrade pog to v4

## 3.2.0 - 15/06/2025

**Features**

- Updated stdlib to 0.60.0 to support the decode API

## 3.1.0 - 30/04/2025

**Features**

- Added functions and changed the API to better interface libraries with cigogne
- Improved performance by reducing the number of calls to the database and the FS
- Creating migration folder on engine creation

## 3.0.0 - 29/04/2025

**Breaking changes**

- Updated the \_migrations table to add a hash of the migration file content

**Features**

- Added a script to migrate from v2 to v3
- Now cigogne returns an error when the migration name is larger than 255 characters

## 2.0.5 - 31/03/2025

**Features**

- Now supporting complex queries with dollar quoted literals and semicolons in literals

## 2.0.4 - 12/03/2025

**Features**

- Using a generated integer instead of a serial for the migration id to comply with SQL standards & best practices

## 2.0.3 - 01/03/2025

**Features**

- Creating the migration folder if it doesn't exist
- More logs & better error messages

## 2.0.2 - 06/01/2025

**Fixes**

- cigogne's zero migration (the one creating the \_migrations table) is executed only when needed

## 2.0.1 - 28/12/2024

**Features**

- Update pog to v3

## 2.0.0 - 21/12/2024

**Breaking changes**

- Using timestamps and names to identify migrations instead of migration numbers
- Changed how commands work as a result

**Features**

- Added the "new" command

## 1.0.0 - 28/11/2024

Initial release of cigogne

**Features**

- Detect migrations in SQL files in migrations directories
- Migrate up, down, to and to last
- Commands accessible via API or CLI
- Commands create/update a schema file
