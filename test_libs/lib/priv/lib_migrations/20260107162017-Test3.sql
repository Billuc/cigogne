--- migration:up:disable_transaction
CREATE TABLE test3 (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL
);

--- migration:down
DROP TABLE IF EXISTS test3;

--- migration:end
