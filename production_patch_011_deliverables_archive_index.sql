-- Patch for production: the Deliverables Completed Archive search now
-- filters on status = 'Delivered' and sorts/filters on delivered_at —
-- a composite index serves both, same pattern as production_patch_009
-- (issue_reports) and production_patch_010 (projects).

create index if not exists deliverables_status_delivered_at_idx
  on deliverables(status, delivered_at desc);
