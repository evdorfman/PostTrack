-- Patch for production: drops the team_members foreign keys on
-- deliverables.editor_id/animator_id/producer_id and activity_log.actor_id.
-- Found via a real failure: live data has at least one deliverable
-- referencing a team member no longer in the roster (editor_id=8), which
-- the app has always silently tolerated (shows as unassigned) but these
-- constraints didn't. Dropping them brings the schema back in line with
-- actual behavior rather than "fixing" real, pre-existing data.
--
-- Run this, then re-run production_backfill.sql.

alter table deliverables drop constraint if exists deliverables_editor_id_fkey;
alter table deliverables drop constraint if exists deliverables_animator_id_fkey;
alter table deliverables drop constraint if exists deliverables_producer_id_fkey;
alter table activity_log drop constraint if exists activity_log_actor_id_fkey;
