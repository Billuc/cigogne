--- migration:up
--- 20250913102033-lib
--- 20250913091039-Test2
alter table books
drop column price;
--- 20250913083538-Test1
drop table books;
--- migration:down
--- 20250913102033-lib
--- 20250913083538-Test1
create table if not exists books (
    id serial primary key,
    title text,
    rating int
);
--- 20250913091039-Test2
alter table books
add price float;
update books
set price = 26.5;
--- migration:end
