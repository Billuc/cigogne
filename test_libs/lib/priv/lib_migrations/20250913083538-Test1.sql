--- migration:up
create table if not exists books (
  id: serial primary key,
  title: text,
  rating: int,
);

--- migration:down
drop table books;

--- migration:end
