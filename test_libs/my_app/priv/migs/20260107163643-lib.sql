--- migration:up

--- 20260107162021-Test4
CREATE TABLE test4 (
    id SERIAL PRIMARY KEY,
    description TEXT NOT NULL
);
--- migration:down

--- 20260107162021-Test4
DROP TABLE IF EXISTS test4;
--- migration:end