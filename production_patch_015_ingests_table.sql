-- Patch for production: normalizes standalone media ingests (today
-- project.ingest_dates, a jsonb array that grows without bound on any
-- project that stays active a long time) into their own indexed table —
-- the same treatment deliverables/productions already got.
--
-- Production-sourced ingests (a shoot's own ingest info, stored on
-- productions.ingest) are NOT duplicated into this table — the
-- productions table is already normalized/indexed, so the app queries it
-- directly (filtering the ingest jsonb's own datetime/completedAt keys)
-- instead of copying that data a second place.
--
-- `seq` is the ingest's stable per-project display number
-- (ProjectCode_IngestNNN) — assigned once, at creation, so it never
-- shifts just because an older ingest scrolled out of the app's default
-- (not-yet-completed) view. The backfill assigns it from ingest_dates'
-- existing array order.

create table if not exists ingests (
  id                      uuid primary key default gen_random_uuid(),
  legacy_id               bigint,
  project_id              bigint not null references projects(id) on delete cascade,
  seq                     integer,
  datetime                timestamptz,
  completed_at            timestamptz,
  location                text,
  num_files               integer,
  total_size_gb           numeric,
  curator_link            text,
  transcript_needed       boolean default false,
  transcript_link         text,
  trint_links             jsonb default '[]'::jsonb,
  media_rows              jsonb default '[]'::jsonb,
  review_link             text,
  linked_review_link_ids  jsonb default '[]'::jsonb,
  review_link_del_ids     jsonb default '[]'::jsonb,
  media_source            text,
  notes                   text,
  call_sheet              jsonb,
  status                  text,
  created_at              timestamptz default now(),
  updated_at              timestamptz default now()
);
create index if not exists ingests_project_id_idx    on ingests(project_id);
create index if not exists ingests_completed_at_idx  on ingests(completed_at);
create index if not exists ingests_datetime_idx      on ingests(datetime desc);

-- Same security model as every other table (see staging_schema.sql's RLS
-- block): any signed-in user can read/write every row.
alter table ingests enable row level security;
do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'ingests' and policyname = 'authenticated full access'
  ) then
    create policy "authenticated full access" on ingests for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
  end if;
end $$;

-- One-time backfill from projects.ingest_dates — preserves each entry's
-- array position as its permanent `seq`.
insert into ingests (
  legacy_id, project_id, seq, datetime, completed_at, location, num_files, total_size_gb,
  curator_link, transcript_needed, transcript_link, trint_links, media_rows, review_link,
  linked_review_link_ids, review_link_del_ids, media_source, notes, call_sheet, status
)
select
  (ig->>'id')::bigint,
  p.id,
  idx::integer, -- jsonb_array_elements ... with ordinality is already 1-based
  nullif(ig->>'datetime','')::timestamptz,
  nullif(ig->>'completedAt','')::timestamptz,
  ig->>'location',
  nullif(ig->>'numFiles','')::integer,
  nullif(ig->>'totalSizeGB','')::numeric,
  ig->>'curatorLink',
  coalesce((ig->>'transcriptNeeded')::boolean, false),
  ig->>'transcriptLink',
  coalesce(ig->'trintLinks', '[]'::jsonb),
  coalesce(ig->'mediaRows', '[]'::jsonb),
  ig->>'reviewLink',
  coalesce(ig->'linkedReviewLinkIds', '[]'::jsonb),
  coalesce(ig->'reviewLinkDelIds', '[]'::jsonb),
  ig->>'mediaSource',
  ig->>'notes',
  ig->'callSheet',
  coalesce(ig->>'status', 'Not Received')
from projects p, jsonb_array_elements(p.ingest_dates) with ordinality as t(ig, idx)
where jsonb_typeof(p.ingest_dates) = 'array'
  and not exists (select 1 from ingests i where i.legacy_id = (ig->>'id')::bigint and i.project_id = p.id);
