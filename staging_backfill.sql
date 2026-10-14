-- PostTrack staging backfill
-- Run this in the staging project's SQL Editor AFTER staging_schema.sql and
-- staging_seed.sql. Reads the nested JSON on projects.deliverables /
-- projects.productions (today's production format), plus the Work Review
-- Sessions blob in app_kv, and populates the new normalized tables
-- (deliverables, review_rounds, productions, work_review_sessions) from it.
--
-- Safe to re-run: it truncates its own target tables first, so running it
-- twice in a row just re-migrates from the same source rather than
-- duplicating rows. It never touches `projects`/`app_kv` themselves.
--
-- The seed data doesn't exercise Work Review Session grouping, so
-- work_review_sessions will come back empty here — that's expected, not a
-- bug; see production_backfill.sql for where this actually populates.

begin;

truncate table review_rounds, deliverables, productions, work_review_sessions,
  setup_types, production_presets, custom_tasks,
  gear, furniture, props, screen_content_options, unavailability, talent_roster,
  nudges, intakes, bec_requests, media_cards, workstations,
  vendor_companies, reviewer_names, studio_space_meta, studio_spaces,
  app_lists, resource_config, tab_locks cascade;

-- Deliverables (top-level array on each project; production-nested
-- deliverables, if any exist in real data, are intentionally out of scope —
-- see the "production-nested deliverables" note in the Airtable requirements
-- doc for why: the app's own edit path never reaches those today either).
insert into deliverables (
  legacy_id, project_id, title, status, deadline, delivered_at,
  editor_id, animator_id, producer_id, deliverable_type, aspect_ratio, quality,
  workstream, business_unit,
  frame_link, frame_pw, frame_internal_url, video_length, file_path,
  dist_platforms, use_case_limitations, approved_uses, speakers, keywords, notes,
  total_revisions, estimated_hours_override,
  contains_ai, ai_tools, greenscreen, captions_needed, srt_delivered, srt_frame_url, watermark,
  bxtv_link
)
select
  (d.elem->>'id')::bigint,
  p.id,
  d.elem->>'title',
  d.elem->>'status',
  nullif(d.elem->>'deadline','')::date,
  nullif(d.elem->>'deliveredAt','')::date,
  nullif(d.elem->>'editorId','')::bigint,
  nullif(d.elem->>'animatorId','')::bigint,
  nullif(d.elem->>'producerId','')::bigint,
  d.elem->>'deliverableType',
  d.elem->>'aspectRatio',
  d.elem->>'quality',
  d.elem->>'workstream',
  d.elem->>'businessUnit',
  d.elem->>'frameLink',
  d.elem->>'framePW',
  d.elem->>'frameInternalUrl',
  d.elem->>'videoLength',
  d.elem->>'filePath',
  coalesce((select array_agg(x) from jsonb_array_elements_text(d.elem->'distPlatforms') x), '{}'),
  coalesce((select array_agg(x) from jsonb_array_elements_text(d.elem->'useCaseLimitations') x), '{}'),
  coalesce((select array_agg(x) from jsonb_array_elements_text(d.elem->'approvedUses') x), '{}'),
  coalesce(d.elem->'speakers', '[]'::jsonb),
  coalesce((select array_agg(x) from jsonb_array_elements_text(d.elem->'keywords') x), '{}'),
  d.elem->>'notes',
  coalesce((d.elem->>'totalRevisions')::int, 0),
  nullif(d.elem->>'estimatedHoursOverride','')::numeric,
  coalesce((d.elem->>'containsAI')::boolean, false),
  coalesce((select array_agg(x) from jsonb_array_elements_text(d.elem->'aiTools') x), '{}'),
  coalesce((d.elem->>'greenscreen')::boolean, false),
  coalesce((d.elem->>'captionsNeeded')::boolean, false),
  coalesce((d.elem->>'srtDelivered')::boolean, false),
  d.elem->>'srtFrameUrl',
  coalesce((d.elem->>'watermark')::boolean, false),
  d.elem->'bxtvLink'
from projects p, jsonb_array_elements(p.deliverables) as d(elem);

-- Review rounds (nested inside each deliverable's own JSON) — second pass,
-- joined back to the deliverables rows we just inserted via legacy_id so
-- each round gets the deliverable's real new UUID as its foreign key.
-- legacy_work_review_session_id captured here is bookkeeping only — the
-- remap pass below (after work_review_sessions is populated) translates it
-- into the real work_review_session_id.
insert into review_rounds (deliverable_id, label, deadline, reviewers, status, notes, legacy_work_review_session_id)
select
  dl.id,
  r.elem->>'label',
  nullif(r.elem->>'deadline','')::timestamptz,
  coalesce(r.elem->'reviewers', '[]'::jsonb),
  r.elem->>'status',
  r.elem->>'notes',
  nullif(r.elem->>'workReviewSessionId','')::bigint
from projects p
cross join lateral jsonb_array_elements(p.deliverables) as d(elem)
cross join lateral jsonb_array_elements(coalesce(d.elem->'rounds', '[]'::jsonb)) as r(elem)
join deliverables dl
  on dl.project_id = p.id and dl.legacy_id = (d.elem->>'id')::bigint;

-- Productions (top-level array on each project).
insert into productions (
  legacy_id, project_id, title, type, location, start_time, end_time, booked,
  schedule, crew_internal, crew_external, equipment_ids, external_gear,
  media_card_ids, script_file, additional_details, ingest
)
select
  (d.elem->>'id')::bigint,
  p.id,
  d.elem->>'title',
  d.elem->>'type',
  d.elem->>'location',
  nullif(d.elem->>'startTime','')::timestamptz,
  nullif(d.elem->>'endTime','')::timestamptz,
  coalesce((d.elem->>'booked')::boolean, false),
  coalesce(d.elem->'schedule', '[]'::jsonb),
  coalesce(d.elem->'crewInternal', '[]'::jsonb),
  coalesce(d.elem->'crewExternal', '[]'::jsonb),
  coalesce(d.elem->'equipmentIds', '[]'::jsonb),
  coalesce(d.elem->'externalGear', '[]'::jsonb),
  coalesce(d.elem->'mediaCardIds', '[]'::jsonb),
  d.elem->'scriptFile',
  d.elem->>'additionalDetails',
  coalesce(d.elem->'ingest', '{}'::jsonb)
from projects p, jsonb_array_elements(p.productions) as d(elem);

-- Work Review Sessions: one JSON array in app_kv (key "work-review-sessions-v1"),
-- not per-project. Expected to insert zero rows against the seed data/a
-- fresh staging project that's never had that key written.
insert into work_review_sessions (legacy_id, datetime, location, zoom_link, reviewers, notes)
select
  (s.elem->>'id')::bigint,
  nullif(s.elem->>'datetime','')::timestamptz,
  s.elem->>'location',
  s.elem->>'zoomLink',
  coalesce(s.elem->'reviewers', '[]'::jsonb),
  s.elem->>'notes'
from app_kv kv, jsonb_array_elements(kv.value::jsonb) as s(elem)
where kv.key = 'work-review-sessions-v1';

update review_rounds rr
set work_review_session_id = wrs.id
from work_review_sessions wrs
where rr.legacy_work_review_session_id is not null
  and rr.legacy_work_review_session_id = wrs.legacy_id;

-- Setup Types, Production Presets, Custom Tasks: like Work Review Sessions,
-- each lives as one JSON array in app_kv rather than nested on a project.
-- Expected to insert zero rows against the seed data/a fresh staging
-- project that's never had these keys written — that's expected, not a bug.

insert into setup_types (
  legacy_id, name, description, roles, equipment_ids, external_gear,
  floorplan_photo_key, ref_photo_keys, media_card_ids, furniture_ids,
  prop_ids, recording_specs, screen_content, notes
)
select
  s.elem->>'id',
  s.elem->>'name',
  s.elem->>'description',
  coalesce(s.elem->'roles', '[]'::jsonb),
  coalesce(s.elem->'equipmentIds', '[]'::jsonb),
  coalesce(s.elem->'externalGear', '[]'::jsonb),
  s.elem->>'floorplanPhotoKey',
  coalesce(s.elem->'refPhotoKeys', '[]'::jsonb),
  coalesce(s.elem->'mediaCardIds', '[]'::jsonb),
  coalesce(s.elem->'furnitureIds', '[]'::jsonb),
  coalesce(s.elem->'propIds', '[]'::jsonb),
  coalesce(s.elem->'recordingSpecs', '{}'::jsonb),
  coalesce(s.elem->'screenContent', '{}'::jsonb),
  s.elem->>'notes'
from app_kv kv, jsonb_array_elements(kv.value::jsonb) as s(elem)
where kv.key = 'posttrack-setup-types-v1';

insert into production_presets (legacy_id, name, type, sections)
select
  s.elem->>'id',
  s.elem->>'name',
  s.elem->>'type',
  coalesce(s.elem->'sections', '{}'::jsonb)
from app_kv kv, jsonb_array_elements(kv.value::jsonb) as s(elem)
where kv.key = 'posttrack-production-presets-v1';

insert into custom_tasks (legacy_id, project_id, title, due_date, reminders, notes, done)
select
  (s.elem->>'id')::bigint,
  nullif(s.elem->>'projectId','')::bigint,
  s.elem->>'title',
  nullif(s.elem->>'dueDate','')::date,
  coalesce(s.elem->'reminders', '[]'::jsonb),
  s.elem->>'notes',
  coalesce((s.elem->>'done')::boolean, false)
from app_kv kv, jsonb_array_elements(kv.value::jsonb) as s(elem)
where kv.key = 'posttrack-custom-tasks';

-- ───────────────────────── Phase 3: the remaining 18 collections ──────────
-- Same app_kv-blob-to-table pattern as everything above. See
-- staging_schema.sql's Phase 3 section for the id-type reasoning behind
-- each legacy_id column. The seed data doesn't exercise most of these, so
-- expect 0 rows for anything that was never part of staging_seed.sql.

insert into gear (legacy_id, name, category, quantity, notes)
select
  (s.elem->>'id')::bigint,
  s.elem->>'name', s.elem->>'category',
  coalesce((s.elem->>'quantity')::int, 1),
  s.elem->>'notes'
from app_kv kv, jsonb_array_elements(kv.value::jsonb) as s(elem)
where kv.key = 'posttrack-admin-gear';

insert into furniture (legacy_id, name, category)
select s.elem->>'id', s.elem->>'name', coalesce(s.elem->>'category','Furniture')
from app_kv kv, jsonb_array_elements(kv.value::jsonb) as s(elem)
where kv.key = 'posttrack-admin-furniture';

insert into props (legacy_id, name, category)
select s.elem->>'id', s.elem->>'name', coalesce(s.elem->>'category','Prop')
from app_kv kv, jsonb_array_elements(kv.value::jsonb) as s(elem)
where kv.key = 'posttrack-admin-props';

insert into screen_content_options (legacy_id, category, name)
select s.elem->>'id', 'windowWall', s.elem->>'name'
from app_kv kv, jsonb_array_elements(coalesce((kv.value::jsonb)->'windowWall','[]'::jsonb)) as s(elem)
where kv.key = 'posttrack-admin-screen-content'
union all
select s.elem->>'id', 'vpWall', s.elem->>'name'
from app_kv kv, jsonb_array_elements(coalesce((kv.value::jsonb)->'vpWall','[]'::jsonb)) as s(elem)
where kv.key = 'posttrack-admin-screen-content'
union all
select s.elem->>'id', 'frameTv', s.elem->>'name'
from app_kv kv, jsonb_array_elements(coalesce((kv.value::jsonb)->'frameTv','[]'::jsonb)) as s(elem)
where kv.key = 'posttrack-admin-screen-content';

insert into unavailability (legacy_id, member_id, type, label, start_date, end_date, all_day, start_time, end_time, notes)
select
  s.elem->>'id',
  nullif(s.elem->>'memberId','')::bigint,
  s.elem->>'type', s.elem->>'label',
  nullif(s.elem->>'startDate','')::date, nullif(s.elem->>'endDate','')::date,
  coalesce((s.elem->>'allDay')::boolean, true),
  nullif(s.elem->>'startTime','')::time, nullif(s.elem->>'endTime','')::time,
  s.elem->>'notes'
from app_kv kv, jsonb_array_elements(kv.value::jsonb) as s(elem)
where kv.key = 'posttrack-unavailability';

insert into talent_roster (legacy_id, name, category, bio, photo_key, last_booked_at)
select
  s.elem->>'id', s.elem->>'name', s.elem->>'category', s.elem->>'bio',
  s.elem->>'photoKey', nullif(s.elem->>'lastBookedAt','')::date
from app_kv kv, jsonb_array_elements(kv.value::jsonb) as s(elem)
where kv.key = 'posttrack-talent-roster-v1';

insert into nudges (legacy_id, task_key, project_id, task_id, task_label, tab, to_member_id)
select
  (s.elem->>'id')::bigint, s.elem->>'taskKey',
  nullif(s.elem->>'projectId','')::bigint, s.elem->>'taskId', s.elem->>'taskLabel', s.elem->>'tab',
  nullif(s.elem->>'toMemberId','')::bigint
from app_kv kv, jsonb_array_elements(kv.value::jsonb) as s(elem)
where kv.key = 'posttrack-nudges';

insert into intakes (legacy_id, date_received, status, assigned_project_id, fields)
select
  (s.elem->>'id')::bigint,
  nullif(s.elem->>'dateReceived','')::timestamptz,
  s.elem->>'status',
  nullif(s.elem->>'assignedProjectId','')::bigint,
  (s.elem - 'id' - 'dateReceived' - 'status' - 'assignedProjectId')
from app_kv kv, jsonb_array_elements(kv.value::jsonb) as s(elem)
where kv.key = 'posttrack-intakes-v1';

insert into bec_requests (legacy_id, reservation_id, project_id, action, received_at, parsed)
select
  (s.elem->>'id')::bigint, s.elem->>'reservationId',
  nullif(s.elem->>'projectId','')::bigint, s.elem->>'action',
  nullif(s.elem->>'receivedAt','')::timestamptz,
  coalesce(s.elem->'parsed', '{}'::jsonb)
from app_kv kv, jsonb_array_elements(kv.value::jsonb) as s(elem)
where kv.key = 'posttrack-bec-requests-v1';

insert into media_cards (legacy_id, label, category, type, format, capacity_gb, manufacturer, model, folder_name, status, assigned_to, project_ref, home_location, notes)
select
  s.elem->>'id', s.elem->>'label', s.elem->>'category', s.elem->>'type', s.elem->>'format',
  nullif(s.elem->>'capacityGB','')::int, s.elem->>'manufacturer', s.elem->>'model', s.elem->>'folderName',
  s.elem->>'status', s.elem->>'assignedTo', s.elem->>'projectRef', s.elem->>'homeLocation', s.elem->>'notes'
from app_kv kv, jsonb_array_elements(kv.value::jsonb) as s(elem)
where kv.key = 'posttrack-media-cards-v1';

insert into workstations (legacy_id, name, location, machine_type, serial_number, assigned_to, available)
select
  (s.elem->>'id')::bigint, s.elem->>'name', s.elem->>'location', s.elem->>'machineType', s.elem->>'serialNumber',
  nullif(s.elem->>'assignedTo','')::bigint,
  coalesce((s.elem->>'available')::boolean, true)
from app_kv kv, jsonb_array_elements(kv.value::jsonb) as s(elem)
where kv.key = 'posttrack-admin-workstations';

insert into vendor_companies (name)
select distinct s.elem from app_kv kv, jsonb_array_elements_text(kv.value::jsonb) as s(elem)
where kv.key = 'vendor-companies-v1' on conflict (name) do nothing;

insert into reviewer_names (name)
select distinct s.elem from app_kv kv, jsonb_array_elements_text(kv.value::jsonb) as s(elem)
where kv.key = 'reviewer-names-v1' on conflict (name) do nothing;

insert into studio_spaces (name)
select distinct s.elem from app_kv kv, jsonb_array_elements_text(kv.value::jsonb) as s(elem)
where kv.key = 'posttrack-admin-spaces' on conflict (name) do nothing;

insert into studio_space_meta (space_name, is_hmu, is_green_room, is_pcr, suggest_hmu, linked_green_room, crew_call_offset_ms)
select
  kv_pair.key,
  coalesce((kv_pair.value->>'isHMU')::boolean, false),
  coalesce((kv_pair.value->>'isGreenRoom')::boolean, false),
  coalesce((kv_pair.value->>'isPCR')::boolean, false),
  coalesce((kv_pair.value->>'suggestHMU')::boolean, false),
  kv_pair.value->>'linkedGreenRoom',
  coalesce((kv_pair.value->>'crewCallOffsetMs')::int, 0)
from app_kv kv, jsonb_each(kv.value::jsonb) as kv_pair(key,value)
where kv.key = 'posttrack-admin-meta'
  and kv_pair.key in (select name from studio_spaces);

insert into app_lists (workstreams, business_units, production_types, deliverable_statuses, anim_batch_statuses, admin_roles, design_roles, production_roles, post_production_roles)
select
  coalesce((kv.value::jsonb)->'workstreams','[]'::jsonb),
  coalesce((kv.value::jsonb)->'businessUnits','[]'::jsonb),
  coalesce((kv.value::jsonb)->'productionTypes','[]'::jsonb),
  coalesce((kv.value::jsonb)->'deliverableStatuses','[]'::jsonb),
  coalesce((kv.value::jsonb)->'animBatchStatuses','[]'::jsonb),
  coalesce((kv.value::jsonb)->'adminRoles','[]'::jsonb),
  coalesce((kv.value::jsonb)->'designRoles','[]'::jsonb),
  coalesce((kv.value::jsonb)->'productionRoles','[]'::jsonb),
  coalesce((kv.value::jsonb)->'postProductionRoles','[]'::jsonb)
from app_kv kv where kv.key = 'posttrack-lists';

insert into resource_config (deliverable_type_hours, status_remaining_pct, media_task_hours, ingest_remaining_pct, assignable_percent, default_hours_per_animation, hours_per_shoot, hours_per_deliverable)
select
  coalesce((kv.value::jsonb)->'deliverableTypeHours','{}'::jsonb),
  coalesce((kv.value::jsonb)->'statusRemainingPct','{}'::jsonb),
  coalesce((kv.value::jsonb)->'mediaTaskHours','{}'::jsonb),
  coalesce((kv.value::jsonb)->'ingestRemainingPct','{}'::jsonb),
  coalesce(((kv.value::jsonb)->>'assignablePercent')::numeric, 0.85),
  coalesce(((kv.value::jsonb)->>'defaultHoursPerAnimation')::numeric, 2),
  coalesce(((kv.value::jsonb)->>'hoursPerShoot')::numeric, 8),
  coalesce(((kv.value::jsonb)->>'hoursPerDeliverable')::numeric, 0.5)
from app_kv kv where kv.key = 'posttrack-resource-config';

insert into tab_locks (locks)
select coalesce(kv.value::jsonb, '{}'::jsonb)
from app_kv kv where kv.key = 'posttrack-tab-locks';

commit;

-- ───────────────────────── Verification ────────────────────────────────
-- Run these (or just look at the output above) and send me what you see —
-- expected, from the seed data: 4 deliverables, 3 review rounds, 1 production,
-- 0 work_review_sessions (seed data doesn't exercise this).

select 'deliverables' as table_name, count(*) from deliverables
union all
select 'review_rounds', count(*) from review_rounds
union all
select 'productions', count(*) from productions
union all
select 'work_review_sessions', count(*) from work_review_sessions
union all
select 'setup_types', count(*) from setup_types
union all
select 'production_presets', count(*) from production_presets
union all
select 'custom_tasks', count(*) from custom_tasks
union all
select 'gear', count(*) from gear
union all
select 'furniture', count(*) from furniture
union all
select 'props', count(*) from props
union all
select 'screen_content_options', count(*) from screen_content_options
union all
select 'unavailability', count(*) from unavailability
union all
select 'talent_roster', count(*) from talent_roster
union all
select 'nudges', count(*) from nudges
union all
select 'intakes', count(*) from intakes
union all
select 'bec_requests', count(*) from bec_requests
union all
select 'media_cards', count(*) from media_cards
union all
select 'workstations', count(*) from workstations
union all
select 'vendor_companies', count(*) from vendor_companies
union all
select 'reviewer_names', count(*) from reviewer_names
union all
select 'studio_spaces', count(*) from studio_spaces
union all
select 'studio_space_meta', count(*) from studio_space_meta
union all
select 'app_lists', count(*) from app_lists
union all
select 'resource_config', count(*) from resource_config
union all
select 'tab_locks', count(*) from tab_locks;

select p.name as project, d.title as deliverable, d.status, d.deadline, d.delivered_at,
       (select count(*) from review_rounds r where r.deliverable_id = d.id) as round_count
from deliverables d join projects p on p.id = d.project_id
order by p.name, d.title;
