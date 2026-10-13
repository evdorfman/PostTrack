-- Patch for production: adds the work_review_sessions table and the
-- bookkeeping needed to remap review_rounds.work_review_session_id during
-- a backfill. Run this, then re-run production_backfill.sql (the updated
-- version, sent separately) to actually populate the grouping.

create table if not exists work_review_sessions (
  id          uuid primary key default gen_random_uuid(),
  legacy_id   bigint,
  datetime    timestamptz,
  location    text,
  zoom_link   text,
  reviewers   jsonb default '[]'::jsonb,
  notes       text,
  created_at  timestamptz default now()
);
create index if not exists work_review_sessions_legacy_id_idx on work_review_sessions(legacy_id);

alter table review_rounds add column if not exists legacy_work_review_session_id bigint;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'review_rounds_work_review_session_id_fkey'
  ) then
    alter table review_rounds
      add constraint review_rounds_work_review_session_id_fkey
      foreign key (work_review_session_id) references work_review_sessions(id) on delete set null;
  end if;
end $$;

alter table work_review_sessions enable row level security;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'work_review_sessions' and policyname = 'authenticated full access'
  ) then
    create policy "authenticated full access" on work_review_sessions
      for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
  end if;
end $$;
