-- PostTrack PRODUCTION backfill
-- Run this in the live project's SQL Editor AFTER production_schema_new_tables.sql.
-- Reads the nested JSON on projects.deliverables / projects.productions
-- (today's live format) and populates the new normalized tables
-- (deliverables, review_rounds, productions) from it.
--
-- Non-destructive: only ever reads from `projects`, never writes to it. The
-- JSON columns stay exactly as they are — nothing here can lose data, only
-- need a redo. Safe to re-run: it truncates its own target tables first, so
-- running it twice in a row just re-migrates from the same source rather
-- than duplicating rows.
--
-- Known limitations, scoped out deliberately rather than by oversight:
--  - A review round's `workReviewSessionId` (the id that groups several
--    rounds, often across deliverables, into one shared review session —
--    see the Project Schedule work) is NOT carried over; every migrated
--    round's `work_review_session_id` comes in null. The grouping
--    information isn't lost (the original JSON is untouched), just not yet
--    translated — a legacy_id-style remapping pass can add it later if the
--    normalized tables need to represent it. Worth knowing before relying
--    on "work review session" grouping from the new tables specifically.
--  - Production-nested deliverables, if any exist in real data, are out of
--    scope here for the same reason the app's own edit path never reaches
--    them today — see the "production-nested deliverables" note in the
--    Airtable requirements doc.

begin;

truncate table review_rounds, deliverables, productions cascade;

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

insert into review_rounds (deliverable_id, label, deadline, reviewers, status, notes)
select
  dl.id,
  r.elem->>'label',
  nullif(r.elem->>'deadline','')::timestamptz,
  coalesce(r.elem->'reviewers', '[]'::jsonb),
  r.elem->>'status',
  r.elem->>'notes'
from projects p
cross join lateral jsonb_array_elements(p.deliverables) as d(elem)
cross join lateral jsonb_array_elements(coalesce(d.elem->'rounds', '[]'::jsonb)) as r(elem)
join deliverables dl
  on dl.project_id = p.id and dl.legacy_id = (d.elem->>'id')::bigint;

insert into productions (
  legacy_id, project_id, title, location, start_time, end_time, booked,
  schedule, crew_internal, crew_external, equipment_ids, external_gear,
  media_card_ids, script_file, additional_details, ingest
)
select
  (d.elem->>'id')::bigint,
  p.id,
  d.elem->>'title',
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

commit;

-- ───────────────────────── Verification ────────────────────────────────
-- No fixed expected counts here (unlike staging's test fixtures) — sanity
-- check these against what you know is roughly true of real data: does the
-- deliverables count look right for the number of active projects? Spot-
-- check a project or two by name against what you see in the app.

select 'deliverables' as table_name, count(*) from deliverables
union all
select 'review_rounds', count(*) from review_rounds
union all
select 'productions', count(*) from productions;

select p.name as project, count(d.id) as deliverable_count,
       count(d.id) filter (where d.status='Delivered') as delivered_count
from projects p left join deliverables d on d.project_id = p.id
group by p.name
order by p.name;
