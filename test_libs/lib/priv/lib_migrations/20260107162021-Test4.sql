--- migration:up
CREATE TABLE test4 (
    id SERIAL PRIMARY KEY,
    description TEXT NOT NULL
);

--- migration:down
DROP TABLE IF EXISTS test4;

--- migration:end
