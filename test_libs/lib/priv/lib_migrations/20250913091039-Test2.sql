--- migration:up
alter table books
add price float;

update books
set price = 26.5;

--- migration:down
alter table books
drop column price;

--- migration:end
