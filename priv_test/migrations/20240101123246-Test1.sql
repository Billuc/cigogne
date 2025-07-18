--- migration:up
create table todos(id uuid primary key, title text);
--- migration:down
drop table todos;
--- migration:end

