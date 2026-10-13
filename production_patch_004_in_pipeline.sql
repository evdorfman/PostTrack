-- Patch for production: adds the `in_pipeline` column to `projects`.
-- `inPipeline` is used throughout the Pipeline page's UI (the add/remove
-- toggle buttons, the "X total tracked" count, the filtering) but was never
-- actually persisted — rowToProject/projectToRow never mapped it, so every
-- toggle looked like it worked for the rest of that session, then silently
-- reverted to unset on the next reload. Found and flagged while mapping the
-- schema for the Supabase normalization pass, fixed now.
--
-- Safe to run on the live table — doesn't touch any existing rows (new
-- column defaults to false for everything already there, i.e. "not in the
-- pipeline", which matches today's effective behavior since the flag has
-- never actually survived a reload for anyone).

alter table projects add column if not exists in_pipeline boolean default false;
