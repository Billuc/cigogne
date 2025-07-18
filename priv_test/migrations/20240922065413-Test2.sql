--- migration:up
create table tags(id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY, tag text not null);
alter table todos add column tag integer references tags(id);
--- migration:down
alter table todos drop column tag;
drop table tags;
--- migration:end 

