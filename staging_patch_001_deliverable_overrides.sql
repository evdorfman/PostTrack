-- Patch for staging: adds two columns to `deliverables` that were missing
-- from the original staging_schema.sql (a deliverable can override its
-- project's workstream/business unit; found while designing the write path).
-- Safe to run on the already-set-up staging project — doesn't touch any
-- existing rows or tables. staging_schema.sql itself has also been updated
-- so a fresh setup from scratch wouldn't need this patch.

alter table deliverables add column if not exists workstream text;
alter table deliverables add column if not exists business_unit text;
