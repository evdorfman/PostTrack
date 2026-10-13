-- Patch for production: makes `updated_at` actually update on UPDATE.
-- It only had a column default (now() on INSERT), so every row still showed
-- its original backfill timestamp no matter how many times it was edited —
-- not wrong data, just a column that was never being told to refresh itself.
-- Postgres needs an explicit trigger for this; there's no built-in
-- "auto-update on change" behavior the way the INSERT default provides.

create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists set_updated_at on deliverables;
create trigger set_updated_at before update on deliverables
  for each row execute function set_updated_at();

drop trigger if exists set_updated_at on productions;
create trigger set_updated_at before update on productions
  for each row execute function set_updated_at();
