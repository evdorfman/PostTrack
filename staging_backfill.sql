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

truncate table review_rounds, deliverables, productions, work_review_sessions cascade;

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
select 'work_review_sessions', count(*) from work_review_sessions;

select p.name as project, d.title as deliverable, d.status, d.deadline, d.delivered_at,
       (select count(*) from review_rounds r where r.deliverable_id = d.id) as round_count
from deliverables d join projects p on p.id = d.project_id
order by p.name, d.title;
