-- Patch for production: the active-issues fetch now filters on resolved
-- and the archive search filters/sorts on resolved + created_at together
-- (see issueReports' and searchResolvedIssues' comments in the JS) — a
-- composite index serves both better than the two separate single-column
-- indexes from production_patch_008.

create index if not exists issue_reports_resolved_created_at_idx
  on issue_reports(resolved, created_at desc);
