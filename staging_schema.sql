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
  bxtv_meta       jsonb,
  in_pipeline     boolean default false
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

-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 3: the remaining app_kv-backed collections (see the "what else
-- should be its own table" conversation this landed in). Same uuid-surrogate
-- + legacy_id pattern as deliverables/productions/setup_types for anything
-- with real per-item ids (protects against uid()'s per-browser-tab counter
-- colliding between two people); plain string primary keys for collections
-- where the app itself has no id concept, just a flat list of distinct
-- strings. Every id-type decision below came from reading the actual
-- object-construction code, not from guessing off the field name — several
-- of these mix hardcoded string ids (seed data) with numeric uid() ones
-- (runtime adds) in the SAME collection, which is why most of these are
-- `legacy_id text` even though they look numeric at a glance.

create table if not exists gear (
  id            uuid primary key default gen_random_uuid(),
  legacy_id     bigint,  -- always uid() — no mixed-id risk here, unlike most of the rest of this section
  name          text,
  category      text,
  quantity      integer default 1,
  notes         text,
  created_at    timestamptz default now()
);

create table if not exists furniture (
  id            uuid primary key default gen_random_uuid(),
  legacy_id     text,  -- seed ids are "furn-001" style, runtime-added ones are "furn-<timestamp>" — both non-numeric strings
  name          text,
  category      text default 'Furniture',
  created_at    timestamptz default now()
);

create table if not exists props (
  id            uuid primary key default gen_random_uuid(),
  legacy_id     text,  -- runtime-added ids are "prop-<timestamp>" strings; no seed data today
  name          text,
  category      text default 'Prop',
  created_at    timestamptz default now()
);

-- Collapses windowWall/vpWall/frameTv into one table with a category column
-- rather than three separate tables — the app's own runtime-added ids share
-- one "sc-<timestamp>" prefix across all three categories, so category has
-- to be a real column regardless; no reason to also split the table.
create table if not exists screen_content_options (
  id            uuid primary key default gen_random_uuid(),
  legacy_id     text,  -- seed ids are "ww-001"/"vp-001"/"ftv-001" style, runtime-added ones are "sc-<timestamp>"
  category      text check (category in ('windowWall','vpWall','frameTv')),
  name          text,
  created_at    timestamptz default now()
);
create index if not exists screen_content_options_category_idx on screen_content_options(category);

create table if not exists unavailability (
  id            uuid primary key default gen_random_uuid(),
  legacy_id     text,  -- always String(Date.now()) locally — a numeric-looking string, never actually typed as a number
  member_id     bigint,  -- intentionally no FK: same "real data can have stale ids" reasoning as deliverables.editor_id
  type          text,
  label         text,
  start_date    date,
  end_date      date,
  all_day       boolean default true,
  start_time    time,
  end_time      time,
  notes         text,
  created_at    timestamptz default now()
);
create index if not exists unavailability_member_id_idx on unavailability(member_id);

create table if not exists talent_roster (
  id              uuid primary key default gen_random_uuid(),
  legacy_id       text,  -- seed ids are "tal-001" style, runtime-added ones are "tal-<uid()>" — different string formats, both non-numeric
  name            text,
  category        text,
  bio             text,
  photo_key       text,
  last_booked_at  date,
  created_at      timestamptz default now()
);

create table if not exists nudges (
  id              uuid primary key default gen_random_uuid(),
  legacy_id       bigint,  -- always uid() — safe
  task_key        text,
  project_id      bigint references projects(id) on delete cascade,
  task_id         text,
  task_label      text,
  tab             text,
  to_member_id    bigint,  -- intentionally no FK, same reasoning as elsewhere
  created_at      timestamptz default now()
);
create index if not exists nudges_task_key_idx on nudges(task_key);
create index if not exists nudges_project_id_idx on nudges(project_id);

create table if not exists intakes (
  id                    uuid primary key default gen_random_uuid(),
  legacy_id             bigint,  -- always uid() — safe
  date_received         timestamptz,
  status                text,
  assigned_project_id   bigint references projects(id) on delete set null,
  fields                jsonb default '{}'::jsonb,  -- all ~48 free-text SmartSheet-paste fields (see INTAKE_FIELD_DEFS) — loosely structured and rarely queried by individual key, so jsonb rather than 48 columns
  created_at            timestamptz default now()
);

create table if not exists bec_requests (
  id              uuid primary key default gen_random_uuid(),
  legacy_id       bigint,  -- always uid() — safe
  reservation_id  text,
  project_id      bigint references projects(id) on delete cascade,
  action          text,  -- "created" | "updated"
  received_at     timestamptz,
  parsed          jsonb default '{}'::jsonb,  -- the full parsed GCS Banquet Event Order — variable shape, not worth normalizing further
  created_at      timestamptz default now()
);
create index if not exists bec_requests_project_id_idx on bec_requests(project_id);

-- legacy_id stays text (not bigint) even though most runtime-added rows get
-- a numeric uid(): ~110 seed rows ship with hand-chosen string slugs
-- ("bec-01", "ssd-43-1", etc.) living in the SAME collection, so a numeric
-- column would silently break on every one of them.
create table if not exists media_cards (
  id              uuid primary key default gen_random_uuid(),
  legacy_id       text,
  label           text,
  category        text,
  type            text,
  format          text,
  capacity_gb     integer,
  manufacturer    text,
  model           text,
  folder_name     text,
  status          text,
  assigned_to     text,  -- free text (a person's name), not a team_members FK
  project_ref     text,  -- free text (a project code), not a projects FK
  home_location   text,
  notes           text,
  created_at      timestamptz default now()
);

create table if not exists workstations (
  id              uuid primary key default gen_random_uuid(),
  legacy_id       bigint,  -- always uid() — safe
  name            text,
  location        text,  -- free text, e.g. "TBD" — not a studio_spaces FK despite the similar name
  machine_type    text,
  serial_number   text,
  assigned_to     bigint,  -- intentionally no FK, same reasoning as elsewhere
  available       boolean default true,
  created_at      timestamptz default now()
);

-- Plain string lists — the app has no id concept for these at all (identity
-- IS the string), so no uuid surrogate/legacy_id bookkeeping is needed.
create table if not exists vendor_companies (
  name          text primary key,
  created_at    timestamptz default now()
);

create table if not exists reviewer_names (
  name          text primary key,
  created_at    timestamptz default now()
);

-- Renaming a space is already destructive to anything that referenced the
-- old name as a literal string (same behavior the app has today) — this
-- just mirrors that, not a new fragility introduced by normalizing it.
create table if not exists studio_spaces (
  name          text primary key,
  created_at    timestamptz default now()
);

create table if not exists studio_space_meta (
  space_name            text primary key references studio_spaces(name) on delete cascade,
  is_hmu                boolean default false,
  is_green_room         boolean default false,
  is_pcr                boolean default false,
  suggest_hmu           boolean default false,
  linked_green_room     text,
  crew_call_offset_ms   integer default 0
);

-- ───────────────────────── Singleton config rows ───────────────────────────
-- Three app-wide settings objects, not collections — one fixed row each
-- (id=1, enforced by the check constraint) rather than a uuid-keyed table,
-- since there's exactly one of each and nothing ever inserts a second.

create table if not exists app_lists (
  id                      smallint primary key default 1 check (id = 1),
  workstreams             jsonb default '[]'::jsonb,
  business_units          jsonb default '[]'::jsonb,
  production_types        jsonb default '[]'::jsonb,
  deliverable_statuses    jsonb default '[]'::jsonb,
  anim_batch_statuses     jsonb default '[]'::jsonb,
  admin_roles             jsonb default '[]'::jsonb,
  design_roles            jsonb default '[]'::jsonb,
  production_roles        jsonb default '[]'::jsonb,
  post_production_roles   jsonb default '[]'::jsonb,
  updated_at              timestamptz default now()
);

create table if not exists resource_config (
  id                              smallint primary key default 1 check (id = 1),
  deliverable_type_hours          jsonb default '{}'::jsonb,
  status_remaining_pct            jsonb default '{}'::jsonb,
  media_task_hours                jsonb default '{}'::jsonb,
  ingest_remaining_pct            jsonb default '{}'::jsonb,
  assignable_percent              numeric,
  default_hours_per_animation     numeric,
  hours_per_shoot                 numeric,
  hours_per_deliverable           numeric,
  updated_at                      timestamptz default now()
);

create table if not exists tab_locks (
  id            smallint primary key default 1 check (id = 1),
  locks         jsonb default '{}'::jsonb,  -- {resourcing: [...roles], budget: [...roles]} — open-ended key set, see research notes
  updated_at    timestamptz default now()
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
    'custom_tasks','activity_log','setup_types','production_presets','work_review_sessions',
    'gear','furniture','props','screen_content_options','unavailability','talent_roster',
    'nudges','intakes','bec_requests','media_cards','workstations',
    'vendor_companies','reviewer_names','studio_spaces','studio_space_meta',
    'app_lists','resource_config','tab_locks'
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

drop trigger if exists set_updated_at on app_lists;
create trigger set_updated_at before update on app_lists
  for each row execute function set_updated_at();

drop trigger if exists set_updated_at on resource_config;
create trigger set_updated_at before update on resource_config
  for each row execute function set_updated_at();

drop trigger if exists set_updated_at on tab_locks;
create trigger set_updated_at before update on tab_locks
  for each row execute function set_updated_at();
