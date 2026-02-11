--- migration:up:disable_transaction

--- 20260107162017-Test3
CREATE TABLE test3 (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL
);
--- migration:down

--- 20260107162017-Test3
DROP TABLE IF EXISTS test3;
--- migration:end
