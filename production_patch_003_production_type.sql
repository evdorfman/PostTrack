-- Patch for production: adds the `type` column to `productions`.
-- A production's `type` ("Content Shoot", "Live Broadcast", etc.) drives
-- color coding, shoot-type logic, and is what the UI falls back to as a
-- display name ("<type> <position>") when a production has no custom
-- title — a real, heavily-used field the original schema missed entirely.
-- Found live: searching for "Content Shoot 2" (a computed display name,
-- not a stored value) returned nothing, which led to this gap.
--
-- Safe to run on the already-set-up production table — doesn't touch any
-- existing rows. Run this, then re-run production_backfill.sql to
-- actually populate `type` on existing rows (safe to re-run — it
-- truncates its own target tables first).

alter table productions add column if not exists type text;
