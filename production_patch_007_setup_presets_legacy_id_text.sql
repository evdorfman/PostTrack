-- Follow-up to patch 006: legacy_id on setup_types and production_presets
-- needs to be text, not bigint. The app ships hardcoded defaults with
-- string ids (DEFAULT_SETUP_TYPES uses "setup-001" etc.; the BEC_EVENT_PRESET
-- default uses "preset-ny-bec-event1"), and since the app just appends to
-- those in-memory lists, the string ids end up saved into app_kv right
-- alongside numeric uid()-generated ones. Both tables are still empty
-- (the backfill that hit this error rolled back before committing anything),
-- so this conversion is trivial — nothing to lose.

alter table setup_types alter column legacy_id type text;
alter table production_presets alter column legacy_id type text;
