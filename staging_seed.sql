-- PostTrack staging seed data
-- Run this in the staging project's SQL Editor AFTER staging_schema.sql.
-- Creates a handful of realistic sample team members + projects (with
-- deliverables/productions still nested as JSON, exactly like production
-- today) so there's something real for the backfill script to migrate.
-- Uses an obviously-fake id range (9000s) so it's never confused with
-- anything real.

insert into team_members (id, name, roles, employee_type, available, email, department, rate, skills, work_hours, is_admin) values
(9001, 'Jordan Ellis', ARRAY['Editor']::text[], 'Internal', true, 'jordan@example.com', 'Post Production', '{"type":"salary","amount":null}'::jsonb, ARRAY['Premiere Pro','Color']::text[], '{"days":[1,2,3,4,5],"start":9,"end":17,"timezone":"EST"}'::jsonb, false),
(9002, 'Priya Shah', ARRAY['Producer']::text[], 'Internal', true, 'priya@example.com', 'Production', '{"type":"salary","amount":null}'::jsonb, ARRAY['Production Management']::text[], '{"days":[1,2,3,4,5],"start":9,"end":17,"timezone":"EST"}'::jsonb, true),
(9003, 'Marcus Webb', ARRAY['Animator']::text[], 'Contractor', true, 'marcus@example.com', 'Post Production', '{"type":"hour","amount":120}'::jsonb, ARRAY['After Effects']::text[], '{"days":[1,2,3,4,5],"start":9,"end":17,"timezone":"EST"}'::jsonb, false),
(9004, 'Dana Cruz', ARRAY['Project Manager']::text[], 'Internal', true, 'dana@example.com', 'Production', '{"type":"salary","amount":null}'::jsonb, ARRAY['Scheduling']::text[], '{"days":[1,2,3,4,5],"start":9,"end":17,"timezone":"EST"}'::jsonb, false),
(9005, 'Sam Okafor', ARRAY['Editor']::text[], 'Freelancer', true, 'sam@example.com', 'Post Production', '{"type":"day","amount":900}'::jsonb, ARRAY['Avid']::text[], '{"days":[1,2,3,4,5],"start":9,"end":17,"timezone":"EST"}'::jsonb, false)
on conflict (id) do nothing;

insert into projects (id, name, requester, year, status, workstream, business_unit, deadline, brief_notes, assignees, deliverables, productions) values
(
  9001, 'Fall Product Launch', 'Dana Cruz', 2026, 'Post', 'Brand', 'Marketing', '2026-11-15',
  'Hero video + social cutdowns for the fall launch.',
  '{"Producer":[9002],"Editor":[9001]}'::jsonb,
  '[
    {
      "id": 90011, "title": "Launch Hero Video", "status": "Picture Lock",
      "deadline": "2026-10-20", "editorId": 9001, "producerId": 9002,
      "aspectRatio": "16:9", "deliverableType": "Standard", "quality": "4K",
      "containsAI": false, "srtDelivered": false,
      "rounds": [
        {"id": 900111, "label": "Round 1", "status": "Approved", "deadline": "2026-10-05T17:00:00", "reviewers": ["Dana Cruz"], "notes": ""}
      ]
    },
    {
      "id": 90012, "title": "Social Cutdown :15", "status": "Delivered",
      "deadline": "2026-09-30", "deliveredAt": "2026-09-28", "editorId": 9005,
      "aspectRatio": "9:16", "deliverableType": "Standard",
      "rounds": [
        {"id": 900121, "label": "Round 1", "status": "Approved", "deadline": "2026-09-20T17:00:00", "reviewers": ["Dana Cruz"], "notes": ""}
      ]
    }
  ]'::jsonb,
  '[
    {
      "id": 90013, "title": "Hero Shoot Day 1", "location": "Studio A",
      "startTime": "2026-09-10T09:00:00", "endTime": "2026-09-10T17:00:00", "booked": true,
      "schedule": [
        {"id": 1, "task": "Setup", "time": "09:00", "location": "Studio A", "notes": ""},
        {"id": 2, "task": "Interview - CEO", "time": "10:30", "location": "Studio A", "notes": ""}
      ],
      "additionalDetails": "Needs teleprompter."
    }
  ]'::jsonb
),
(
  9002, 'Q4 Earnings Recap', 'Priya Shah', 2026, 'In Review', 'Investor Relations', 'Corporate', '2026-10-05',
  'Recap video of the Q4 earnings call for internal distribution.',
  '{"Producer":[9002]}'::jsonb,
  '[
    {
      "id": 90021, "title": "Earnings Call Recap", "status": "Rough Cut",
      "deadline": "2026-10-05", "editorId": 9001, "aspectRatio": "16:9",
      "deliverableType": "Standard",
      "rounds": [
        {"id": 900211, "label": "Round 1", "status": "Changes Requested", "deadline": "2026-10-03T17:00:00", "reviewers": ["Priya Shah"], "notes": "Trim the intro."}
      ]
    },
    {
      "id": 90022, "title": "CFO Soundbite Reel", "status": "Not Started",
      "deadline": "2026-11-01", "animatorId": 9003, "aspectRatio": "1:1",
      "deliverableType": "Standard", "rounds": []
    }
  ]'::jsonb,
  '[]'::jsonb
),
(
  9003, 'Internal Culture Video', 'Dana Cruz', 2026, 'Pre-Pro', 'Culture', 'People', '2027-01-15',
  'Prospective project pitched by People team, not yet greenlit.',
  '{"Project Manager":[9004]}'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb
)
on conflict (id) do nothing;
