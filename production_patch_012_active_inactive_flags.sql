-- Patch for production: adds an `active` flag to every reference/metadata
-- collection that's referenced by ID from elsewhere (productions,
-- deliverables, setups) — team members, gear, furniture, props, screen
-- content options, setup types, workstations, talent roster, production
-- presets, and studio spaces (via studio_space_meta, which is already
-- keyed by space name).
--
-- Nothing is ever hard-deleted for these going forward: the app's
-- "delete" action now means "mark inactive" — the row stays, historical
-- records that already reference it are completely unaffected (they
-- still resolve the same name/data they always did), and it just stops
-- being offered as an option for new picks. Reactivating is always
-- possible later.
--
-- Plain string-list collections (app_lists' workstreams/business units/
-- etc., and crew_roles' categories) don't get this — a project's
-- workstream field stores the literal string value directly, not a
-- foreign key, so removing an option from that picklist was already safe
-- for old records; no schema change needed there.

alter table team_members          add column if not exists active boolean not null default true;
alter table gear                  add column if not exists active boolean not null default true;
alter table furniture             add column if not exists active boolean not null default true;
alter table props                 add column if not exists active boolean not null default true;
alter table screen_content_options add column if not exists active boolean not null default true;
alter table setup_types           add column if not exists active boolean not null default true;
alter table workstations          add column if not exists active boolean not null default true;
alter table talent_roster         add column if not exists active boolean not null default true;
alter table production_presets    add column if not exists active boolean not null default true;
alter table studio_space_meta     add column if not exists active boolean not null default true;

create index if not exists team_members_active_idx          on team_members(active);
create index if not exists gear_active_idx                  on gear(active);
create index if not exists furniture_active_idx             on furniture(active);
create index if not exists props_active_idx                 on props(active);
create index if not exists screen_content_options_active_idx on screen_content_options(active);
create index if not exists setup_types_active_idx           on setup_types(active);
create index if not exists workstations_active_idx          on workstations(active);
create index if not exists talent_roster_active_idx         on talent_roster(active);
create index if not exists production_presets_active_idx    on production_presets(active);
