-- One-time repair for team_members rows saved with a partial work_hours
-- object (missing start/end/timezone/days) — see the "+ Add" form reset
-- bug fixed in PostProTrackerV4.jsx (the reset was missing workHours,
-- so every member added after the first one in the same sitting started
-- from undefined, becoming {} in the DB if the Work Hours picker was
-- never touched). This only fills in whatever keys are actually missing —
-- any value already set (e.g. a custom day list) is left untouched.

update team_members
set work_hours = jsonb_build_object(
  'days',     coalesce(work_hours->'days',     '[1,2,3,4,5]'::jsonb),
  'start',    coalesce(work_hours->'start',    '9'::jsonb),
  'end',      coalesce(work_hours->'end',      '17'::jsonb),
  'timezone', coalesce(work_hours->'timezone', '"EST"'::jsonb)
)
where work_hours is null
   or not (work_hours ?& array['days','start','end','timezone']);
