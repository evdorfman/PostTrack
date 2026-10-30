-- Adds an individual start date to deliverables. Previously the only
-- "when can this begin" concept was project-wide (projects.post_start_date),
-- so every deliverable in a project shared one start assumption. Some
-- projects (e.g. a weekly show shot on a rolling basis) need each
-- deliverable's own start date, since each one is shot on a different day —
-- this column is that per-deliverable override; when left null, resource
-- planning and the Editor Calendar fall back to the project's Post Start
-- Date exactly as before (see getDeliverableStartDate in the app).

alter table deliverables add column if not exists start_date timestamptz;
