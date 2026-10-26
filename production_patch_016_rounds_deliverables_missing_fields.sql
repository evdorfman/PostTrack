-- Patch for production: same bug class as 013/014, found via a systematic
-- audit of every rowToX/xToRow mapper pair after the third occurrence of
-- it (productions, then projects) made it clear this needed a full pass
-- rather than fixing instances one at a time as they got reported.
--
-- review_rounds: isWorkReview/reviewRoundId are how a batch of rounds
-- added together (via "Add a Review Round" or "Add a Work Review Round")
-- stays grouped as one event on Calendar views and gets bulk status/
-- deadline updates — see AddReviewRoundModal and the work-review-session
-- deadline-sync logic. Neither field existed on the review_rounds table,
-- so every round's group identity was silently dropped on save; after a
-- reload, a batch-added round looked like an ungrouped single round and
-- stopped receiving the session's bulk updates.
--
-- deliverables: srtNeeded (the "SRT Needed" toggle), qualitiesConfirmed
-- (the readiness-checklist confirmation checkbox), and
-- _reassignmentRequested (the "flag this deliverable" marker set when a
-- producer responds to a new team-member unavailability) were all set and
-- read by the UI but never had a column, so all three silently reverted
-- to their defaults on every reload.

alter table review_rounds add column if not exists is_work_review   boolean default false;
alter table review_rounds add column if not exists review_round_id  text;

alter table deliverables add column if not exists srt_needed              boolean default false;
alter table deliverables add column if not exists qualities_confirmed     boolean default false;
alter table deliverables add column if not exists reassignment_requested  jsonb;
