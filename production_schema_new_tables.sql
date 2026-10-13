-- PostTrack PRODUCTION schema — new normalized tables ONLY
-- Run this in the Supabase SQL Editor for the LIVE production project
-- (the one PostProTrackerV4.jsx's SUPABASE_URL points at).
--
-- Unlike staging_schema.sql, this does NOT include projects/team_members/
-- studio_bookings — those already exist in production exactly as they are;
-- nothing here touches, locks, or reads from them. Every statement below
-- either creates a table that doesn't exist yet or is a no-op if it somehow
-- already does (`if not exists` throughout). This cannot affect anything
-- the live app currently reads or writes: no existing table is altered,
-- and nothing in the shipped app calls these new tables yet
-- (SHADOW_WRITE_DELIVERABLES is false).
--
-- UUID primary keys (not the app's client-side uid() counter, which restarts
-- at 400 per browser session and can collide between two people's tabs) so
-- every row gets a globally-unique id regardless of who/what created it.
-- `legacy_id` is kept only so the backfill script can map an old nested
-- object to its new row; nothing else should read it.

create table if not exists deliverables (
  id                        uuid primary key default gen_random_uuid(),
  legacy_id                 bigint,
  project_id                bigint not null references projects(id) on delete cascade,
  title                     text,
  status                    text,
  deadline                  date,
  delivered_at              date,
  editor_id                 bigint,  -- intentionally no FK: real data has stale ids for removed team members, same as the app tolerates today
  animator_id               bigint,
  producer_id               bigint,
  deliverable_type          text,
  aspect_ratio              text,
  quality                   text,
  workstream                text,  -- per-deliverable override of the project's own workstream
  business_unit             text,  -- per-deliverable override of the project's own business unit
  frame_link                text,
  frame_pw                  text,
  frame_internal_url        text,
  video_length              text,
  file_path                 text,
  dist_platforms            text[] default '{}',
  use_case_limitations      text[] default '{}',
  approved_uses             text[] default '{}',
  speakers                  jsonb default '[]'::jsonb,
  keywords                  text[] default '{}',
  notes                     text,
  total_revisions           integer default 0,
  estimated_hours           numeric,
  estimated_hours_override  numeric,
  contains_ai               boolean default false,
  ai_tools                  text[] default '{}',
  greenscreen               boolean default false,
  captions_needed           boolean default false,
  srt_delivered             boolean default false,
  srt_frame_url             text,
  watermark                 boolean default false,
  bxtv_link                 jsonb,
  created_at                timestamptz default now(),
  updated_at                timestamptz default now()
);
create index if not exists deliverables_project_id_idx on deliverables(project_id);

-- A Work Review Session is a shared meeting (date/time/location/zoom link)
-- that several rounds, often across different deliverables, can attach to
-- at once. Lives app-side as one JSON blob in the generic app_kv table
-- (key "work-review-sessions-v1"), not per-project — this table mirrors it.
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

create table if not exists review_rounds (
  id                              uuid primary key default gen_random_uuid(),
  deliverable_id                  uuid not null references deliverables(id) on delete cascade,
  label                           text,
  deadline                        timestamptz,
  reviewers                       jsonb default '[]'::jsonb,
  status                          text,
  notes                           text,
  work_review_session_id          uuid references work_review_sessions(id) on delete set null,
  legacy_work_review_session_id   bigint,  -- bookkeeping only, for the backfill's remap pass; nothing should read this
  created_at                      timestamptz default now()
);
create index if not exists review_rounds_deliverable_id_idx on review_rounds(deliverable_id);

create table if not exists productions (
  id                   uuid primary key default gen_random_uuid(),
  legacy_id            bigint,
  project_id           bigint not null references projects(id) on delete cascade,
  title                text,
  type                 text,  -- e.g. "Content Shoot", "Live Broadcast" — drives color coding and the shoot-type logic; also what the UI falls back to as a display name ("<type> <position>") when a production has no custom title
  location             text,
  start_time           timestamptz,
  end_time             timestamptz,
  booked               boolean default false,
  setup_type_id        uuid,
  schedule             jsonb default '[]'::jsonb,
  crew_internal        jsonb default '[]'::jsonb,
  crew_external        jsonb default '[]'::jsonb,
  equipment_ids        jsonb default '[]'::jsonb,
  external_gear        jsonb default '[]'::jsonb,
  media_card_ids       jsonb default '[]'::jsonb,
  script_file          jsonb,
  additional_details   text,
  ingest               jsonb default '{}'::jsonb,
  created_at           timestamptz default now(),
  updated_at           timestamptz default now()
);
create index if not exists productions_project_id_idx on productions(project_id);

create table if not exists custom_tasks (
  id          uuid primary key default gen_random_uuid(),
  legacy_id   bigint,
  project_id  bigint references projects(id) on delete cascade,
  title       text,
  due_date    date,
  reminders   jsonb default '[]'::jsonb,
  notes       text,
  done        boolean default false,
  created_at  timestamptz default now()
);
create index if not exists custom_tasks_project_id_idx on custom_tasks(project_id);

create table if not exists activity_log (
  id            uuid primary key default gen_random_uuid(),
  project_id    bigint references projects(id) on delete cascade,
  entity_type   text,
  entity_label  text,
  action        text,
  detail        text,
  actor_id      bigint,
  created_at    timestamptz default now()
);
create index if not exists activity_log_project_id_idx on activity_log(project_id);
create index if not exists activity_log_created_at_idx on activity_log(created_at);

create table if not exists setup_types (
  id                   uuid primary key default gen_random_uuid(),
  legacy_id            text,  -- not bigint: the shipped defaults use string ids like "setup-001"
  name                 text,
  description          text,
  roles                jsonb default '[]'::jsonb,
  equipment_ids        jsonb default '[]'::jsonb,
  external_gear        jsonb default '[]'::jsonb,
  floorplan_photo_key  text,
  ref_photo_keys       jsonb default '[]'::jsonb,
  media_card_ids       jsonb default '[]'::jsonb,
  furniture_ids        jsonb default '[]'::jsonb,
  prop_ids             jsonb default '[]'::jsonb,
  recording_specs      jsonb default '{}'::jsonb,
  screen_content       jsonb default '{}'::jsonb,
  notes                text,
  created_at           timestamptz default now()
);

create table if not exists production_presets (
  id          uuid primary key default gen_random_uuid(),
  legacy_id   text,  -- not bigint: the shipped BEC_EVENT_PRESET default uses a string id ("preset-ny-bec-event1")
  name        text,
  type        text,
  sections    jsonb default '{}'::jsonb,
  created_at  timestamptz default now()
);

-- ───────────────────────── RLS ─────────────────────────────────────────────
-- Matches production's existing security model: any signed-in (authenticated)
-- user can read/write every row — same as projects/team_members/
-- studio_bookings already behave today. Only touches the 7 new tables above;
-- nothing about an existing table's policies changes.

do $$
declare
  t text;
begin
  for t in select unnest(array[
    'deliverables','review_rounds','productions',
    'custom_tasks','activity_log','setup_types','production_presets','work_review_sessions'
  ])
  loop
    execute format('alter table %I enable row level security;', t);
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = t and policyname = 'authenticated full access'
    ) then
      execute format(
        'create policy "authenticated full access" on %I for all using (auth.role() = ''authenticated'') with check (auth.role() = ''authenticated'');',
        t
      );
    end if;
  end loop;
end $$;

-- ───────────────────────── updated_at trigger ──────────────────────────────
-- The column default only covers INSERT; without this, updated_at would
-- stay frozen at its backfill time no matter how many times a row changes.

create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists set_updated_at on deliverables;
create trigger set_updated_at before update on deliverables
  for each row execute function set_updated_at();

drop trigger if exists set_updated_at on productions;
create trigger set_updated_at before update on productions
  for each row execute function set_updated_at();
