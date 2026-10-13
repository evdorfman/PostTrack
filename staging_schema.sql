-- PostTrack staging schema
-- Run this once, in full, in the Supabase SQL Editor for the STAGING project
-- (posttrack-staging / otxyvlcoyoustlcevkiz) — never against the live project.
--
-- Part 1 mirrors production as it exists today (projects/team_members/
-- studio_bookings, with deliverables/productions still nested as JSON on the
-- project row) so staging starts as an equivalent copy of the real schema.
-- Part 2 adds the new normalized tables (deliverables, productions, review
-- rounds, etc. as their own real tables) that the normalization pass is
-- building out. Both exist side by side here so the backfill migration
-- (next step) can read out of Part 1's JSON and write into Part 2's tables
-- without anything else needing to change yet.

-- ───────────────────────── Part 1: baseline (mirrors production) ──────────

create table if not exists team_members (
  id                  bigint primary key,
  name                text not null,
  roles               text[] default '{}',
  employee_type       text,
  available           boolean default true,
  email               text,
  phone               text,
  department          text,
  rate                jsonb default '{}'::jsonb,
  skills              text[] default '{}',
  work_hours          jsonb default '{}'::jsonb,
  assignable_percent  numeric,
  auth_user_id        uuid,
  is_admin            boolean default false,
  color               text
);

create table if not exists projects (
  id              bigint primary key,
  project_code    text,
  name            text not null,
  requester       text,
  year            integer,
  status          text,
  workstream      text,
  business_unit   text,
  deadline        date,
  brief_notes     text,
  keywords        text[] default '{}',
  assignees       jsonb default '{}'::jsonb,
  deliverables    jsonb default '[]'::jsonb,  -- superseded by the `deliverables` table below once cut over
  productions     jsonb default '[]'::jsonb,  -- superseded by the `productions` table below once cut over
  shoots          jsonb default '[]'::jsonb,
  notes           jsonb default '[]'::jsonb,
  ingest_dates    jsonb default '[]'::jsonb,
  closed_at       timestamptz,
  bxtv_refs       jsonb default '[]'::jsonb,
  bxtv_meta       jsonb
);

create table if not exists studio_bookings (
  id                 bigint primary key,
  title              text,
  project_id         bigint references projects(id) on delete set null,
  parent_booking_id  bigint,
  booking_status     text,
  production_type    text,
  location           text,
  start_time         timestamptz,
  end_time           timestamptz,
  crew_call_time     timestamptz,
  notes              text,
  equipment_ids      jsonb default '[]'::jsonb,
  confirmations      jsonb default '[]'::jsonb,
  crew_internal      jsonb default '[]'::jsonb,
  crew_external      jsonb default '[]'::jsonb,
  extra              jsonb default '{}'::jsonb
);

-- ───────────────────────── Part 2: new normalized tables ──────────────────
-- UUID primary keys (not the app's client-side uid() counter, which restarts
-- at 400 in every browser tab and can collide between two people's sessions)
-- so every row gets a globally-unique id regardless of who/what created it.
-- `legacy_id` is kept only so the backfill script can map an old nested
-- object to its new row during migration; nothing else should read it.

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
  srt_delivered              boolean default false,
  srt_frame_url             text,
  watermark                 boolean default false,
  bxtv_link                 jsonb,
  created_at                timestamptz default now(),
  updated_at                timestamptz default now()
);
create index if not exists deliverables_project_id_idx on deliverables(project_id);

create table if not exists review_rounds (
  id                       uuid primary key default gen_random_uuid(),
  deliverable_id           uuid not null references deliverables(id) on delete cascade,
  label                    text,
  deadline                 timestamptz,
  reviewers                jsonb default '[]'::jsonb,
  status                   text,
  notes                    text,
  work_review_session_id   uuid,
  created_at               timestamptz default now()
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
  legacy_id            bigint,
  name                 text,
  description          text,
  roles                jsonb default '[]'::jsonb,
  equipment_ids        jsonb default '[]'::jsonb,
  floorplan_photo_key  text,
  ref_photo_keys       jsonb default '[]'::jsonb,
  created_at           timestamptz default now()
);

create table if not exists production_presets (
  id          uuid primary key default gen_random_uuid(),
  legacy_id   text,
  name        text,
  type        text,
  sections    jsonb default '{}'::jsonb,
  created_at  timestamptz default now()
);

-- ───────────────────────── RLS ─────────────────────────────────────────────
-- Matches today's production security model exactly: any signed-in
-- (authenticated) user can read/write every row. The app itself, not the
-- database, is what currently decides who sees which tab — see the
-- "Known Gaps" section of the Airtable requirements doc for why that's a
-- separate, later conversation rather than something to tighten here.

do $$
declare
  t text;
begin
  for t in select unnest(array[
    'team_members','projects','studio_bookings',
    'deliverables','review_rounds','productions',
    'custom_tasks','activity_log','setup_types','production_presets'
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
