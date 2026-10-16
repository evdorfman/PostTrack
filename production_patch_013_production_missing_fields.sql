-- Patch for production: the `productions` table was created with only a
-- subset of the fields the app actually keeps on a production object.
-- rowToProduction/productionToRow (PostProTrackerV4.jsx) silently dropped
-- everything else on every write, and since REALTIME_PHASE2 turned on
-- live sync for this table, any UPDATE event (even one fired from an
-- unrelated edit, or the writer's own change echoing back) replaced the
-- local production object with a freshly-read-from-row copy that was
-- missing these fields entirely — wiping Studio approval status, setup
-- instances, talent bookings, secondary locations (HMU/Green Room),
-- call sheets and more back to their defaults for everyone watching that
-- project in real time, and on every reload.
--
-- This is what caused "I approved a bunch of Studio productions and they
-- went back to pending" — approving sets status/bookingStatus on the
-- production, but neither column existed, so the approval was never
-- actually saved; the next realtime echo or reload reverted it.

alter table productions add column if not exists status                 text;
alter table productions add column if not exists booking_status         text;
alter table productions add column if not exists studio_note            text;
alter table productions add column if not exists rejection_note         text;
alter table productions add column if not exists notes                  text;
alter table productions add column if not exists crew_call_time         text;
alter table productions add column if not exists secondary_locations    jsonb default '[]'::jsonb;
alter table productions add column if not exists confirmations          jsonb default '[]'::jsonb;
alter table productions add column if not exists talent                 jsonb default '[]'::jsonb;
alter table productions add column if not exists setups                 jsonb default '[]'::jsonb;
alter table productions add column if not exists deliverables           jsonb default '[]'::jsonb;
alter table productions add column if not exists playback_assets        jsonb default '[]'::jsonb;
alter table productions add column if not exists asset_requests         jsonb default '[]'::jsonb;
alter table productions add column if not exists call_sheet             jsonb;
-- Cross-references to a deliverable; stored as text (not a FK) since a
-- deliverable's id may be either a legacy numeric id or a real uuid,
-- same dual-id situation as elsewhere in this schema.
alter table productions add column if not exists feeds_into_id          text;
alter table productions add column if not exists playback_deliverable_id text;

create index if not exists productions_status_idx on productions(status);
