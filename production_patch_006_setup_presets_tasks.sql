-- Patch for production: fixes setup_types, production_presets, and
-- custom_tasks to match their real app data shapes (verified against
-- SetupTypeForm, production preset usage, and InlineAddTask/custom task
-- state in PostProTrackerV4.jsx) before backfilling them for the first time.
-- Safe to run even though these three tables already exist and are empty
-- (never backfilled yet) — no data loss is possible here.

alter table setup_types
  add column if not exists external_gear   jsonb default '[]'::jsonb,
  add column if not exists media_card_ids  jsonb default '[]'::jsonb,
  add column if not exists furniture_ids   jsonb default '[]'::jsonb,
  add column if not exists prop_ids        jsonb default '[]'::jsonb,
  add column if not exists recording_specs jsonb default '{}'::jsonb,
  add column if not exists screen_content  jsonb default '{}'::jsonb,
  add column if not exists notes           text;

-- legacy_id was typed text but uid() (the source of setup/preset ids) always
-- returns a number as a string, so bigint is correct and this table is
-- still empty — nothing to actually convert.
alter table production_presets
  alter column legacy_id type bigint using legacy_id::bigint;

alter table custom_tasks
  add column if not exists legacy_id bigint;
create index if not exists custom_tasks_legacy_id_idx on custom_tasks(legacy_id);
