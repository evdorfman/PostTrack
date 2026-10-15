-- Patch for production: the main projects fetch now filters on
-- closed_at is null (active only), and the Projects Archive search
-- filters/sorts on closed_at is not null + closed_at desc — an index
-- serves both. deliverables/productions/review_rounds already have
-- indexes on their own project_id/deliverable_id foreign keys from
-- earlier patches, so this is the one missing piece.

create index if not exists projects_closed_at_idx on projects(closed_at);
