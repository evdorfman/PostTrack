-- Patch for production: adds issue_reports, a single table for two kinds of
-- entries, distinguished by `source`:
--   'app_error'   — automatically logged by reportSbError (JS) whenever any
--                   Supabase write fails, plus crash reports from the
--                   ProjectOverview error boundary.
--   'user_report' — submitted by anyone via the in-app "Report an Issue"
--                   button.
-- With only one person supporting this app, this is the one place that
-- collects both without relying on whoever hit the problem to notice it
-- themselves and go find a way to mention it.

create table if not exists issue_reports (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz default now(),
  source          text not null check (source in ('app_error','user_report')),
  reporter_email  text,
  reporter_name   text,
  message         text not null,
  context         jsonb default '{}'::jsonb,
  resolved        boolean not null default false,
  resolved_at     timestamptz
);
create index if not exists issue_reports_created_at_idx on issue_reports(created_at desc);
create index if not exists issue_reports_resolved_idx on issue_reports(resolved);

alter table issue_reports enable row level security;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'issue_reports' and policyname = 'authenticated full access'
  ) then
    create policy "authenticated full access" on issue_reports
      for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
  end if;
end $$;

alter publication supabase_realtime add table issue_reports;
