-- Patch for production: same bug class as production_patch_013, this time
-- on the `projects` table itself. rowToProject/projectToRow only ever
-- covered a subset of the fields a project actually carries — the projects
-- auto-save effect does a full upsert via projectToRow on every change, so
-- every field below has been silently dropped on every save since the
-- normalized-table migration, and wiped back to its default on every
-- reload or realtime project update.
--
-- Found while scoping the metrics-dashboard work: `animation` (groups,
-- batches, statuses — the entire Animation tab's data) has ZERO
-- persistence at all — it only ever existed in that browser tab's React
-- state. `budget`, `intakeIds`, `pipelineNotes`, `mamProjectLink`,
-- `trintProjectLink`, `costCode`, `clientDescription`, `_segments`
-- (project-level editor handoffs), and several others are in the same
-- boat. This is the same class of bug as bxtvRefs/bxtvMeta/inPipeline,
-- found and fixed earlier — evidently that audit wasn't exhaustive.

alter table projects add column if not exists animation                jsonb default '{}'::jsonb;
alter table projects add column if not exists segments                 jsonb default '[]'::jsonb;  -- project._segments (editor handoffs)
alter table projects add column if not exists budget                   jsonb default '[]'::jsonb;
alter table projects add column if not exists budget_status            text;
alter table projects add column if not exists cost_code                text;
alter table projects add column if not exists added_to_completes       boolean default false;
alter table projects add column if not exists based_on_existing_material boolean default false;
alter table projects add column if not exists is_big_event             boolean default false;
alter table projects add column if not exists brief_summary            text;
alter table projects add column if not exists client_description       text;
alter table projects add column if not exists pipeline_notes           text;
alter table projects add column if not exists mam_project_link         text;
alter table projects add column if not exists trint_project_link       text;
alter table projects add column if not exists project_brief            jsonb;
alter table projects add column if not exists intake_ids               jsonb default '[]'::jsonb;
alter table projects add column if not exists roles_not_needed         text[] default '{}';
