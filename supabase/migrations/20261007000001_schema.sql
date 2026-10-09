-- Deconstructed: tables, constraints and integrity triggers.
--
-- Design notes
--   * Google content is never stored here. `restaurants` keeps a provider place ID (which may
--     be stored indefinitely) and a latitude/longitude that is purged after 30 days.
--   * A ranking system is a mutable shell; its definitions live in immutable versions.
--     Every rating revision points at one exact version.
--   * Totals are derived in the database from criterion scores. No client value is trusted.

create schema if not exists app_private;

create type public.review_visibility as enum ('public', 'followers', 'private');
create type public.revision_state as enum ('draft', 'active', 'superseded');

-- ---------------------------------------------------------------------------------------
-- People
-- ---------------------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique
    check (username = lower(username) and username ~ '^[a-z0-9_.]{3,24}$'),
  display_name text not null check (char_length(btrim(display_name)) between 1 and 60),
  default_visibility public.review_visibility not null default 'followers',
  default_system_id uuid,
  -- Standard systems this person has put away. They remain readable on old ratings.
  archived_standard_system_ids uuid[] not null default '{}',
  created_at timestamptz not null default now()
);

create table public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  followee_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index follows_followee_idx on public.follows (followee_id);

-- ---------------------------------------------------------------------------------------
-- Restaurants (references only) and saved places
-- ---------------------------------------------------------------------------------------

create table public.restaurants (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('google')),
  provider_place_id text not null check (char_length(provider_place_id) between 1 and 300),
  -- Temporary cache, cleared by app_private.purge_stale_restaurant_locations().
  lat double precision check (lat between -90 and 90),
  lng double precision check (lng between -180 and 180),
  location_cached_at timestamptz,
  created_at timestamptz not null default now(),
  unique (provider, provider_place_id),
  check ((lat is null) = (lng is null) and (lat is null) = (location_cached_at is null))
);

create table public.saved_places (
  user_id uuid not null references public.profiles (id) on delete cascade,
  restaurant_id uuid not null references public.restaurants (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, restaurant_id)
);

-- ---------------------------------------------------------------------------------------
-- Ranking systems
-- ---------------------------------------------------------------------------------------

create table public.ranking_systems (
  id uuid primary key default gen_random_uuid(),
  -- NULL marks a standard system shared by everyone. Only migrations create those.
  owner_id uuid references public.profiles (id) on delete cascade,
  template_key text,
  forked_from_system_id uuid references public.ranking_systems (id) on delete set null,
  name text not null check (char_length(btrim(name)) between 1 and 60),
  description text not null default '' check (char_length(description) <= 600),
  is_archived boolean not null default false,
  current_version_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index ranking_systems_owner_idx on public.ranking_systems (owner_id);

alter table public.profiles
  add constraint profiles_default_system_id_fkey
  foreign key (default_system_id) references public.ranking_systems (id) on delete set null;

-- Unpublished edits. Kept apart from ranking_systems so that people who can read a system
-- through someone's review never see its owner's work in progress.
create table public.ranking_system_drafts (
  system_id uuid primary key references public.ranking_systems (id) on delete cascade,
  definition jsonb not null,
  updated_at timestamptz not null default now()
);

create table public.ranking_system_versions (
  id uuid primary key default gen_random_uuid(),
  system_id uuid not null,
  version_number integer not null check (version_number > 0),
  published_at timestamptz not null default now(),
  unique (system_id, version_number),
  constraint ranking_system_versions_system_id_fkey
    foreign key (system_id) references public.ranking_systems (id) on delete cascade
);

alter table public.ranking_systems
  add constraint ranking_systems_current_version_id_fkey
  foreign key (current_version_id) references public.ranking_system_versions (id)
  deferrable initially deferred;

create table public.ranking_criteria (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references public.ranking_system_versions (id) on delete cascade,
  position integer not null check (position >= 0),
  name text not null check (char_length(btrim(name)) between 1 and 60),
  guidance text not null default '',
  -- MVP rule: positive whole-number maximums.
  max_points smallint not null check (max_points between 1 and 10),
  unique (version_id, position)
);

create table public.criterion_score_levels (
  criterion_id uuid not null references public.ranking_criteria (id) on delete cascade,
  points smallint not null check (points >= 0),
  label text not null default '',
  description text not null check (char_length(btrim(description)) > 0),
  primary key (criterion_id, points)
);

-- ---------------------------------------------------------------------------------------
-- Visits, rating revisions and scores
-- ---------------------------------------------------------------------------------------

create table public.visits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  -- No cascade: a visit outlives changes to the provider's listing.
  restaurant_id uuid not null references public.restaurants (id),
  visited_on date not null check (visited_on <= current_date + 1),
  notes text not null default '' check (char_length(notes) <= 4000),
  dishes text[] not null default '{}' check (coalesce(array_length(dishes, 1), 0) <= 40),
  spend_per_person numeric(10, 2) check (spend_per_person >= 0),
  currency_code text not null default 'USD' check (currency_code ~ '^[A-Z]{3}$'),
  visibility public.review_visibility not null default 'followers',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index visits_user_idx on public.visits (user_id, visited_on desc);
create index visits_restaurant_idx on public.visits (restaurant_id);

create table public.rating_revisions (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid not null references public.visits (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  -- No cascade and no "set null": a version that has been rated with cannot disappear.
  system_version_id uuid not null references public.ranking_system_versions (id),
  state public.revision_state not null default 'draft',
  total smallint check (total between 0 and 10),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check ((state = 'draft') = (total is null)),
  check ((state = 'draft') = (completed_at is null))
);
-- A visit has at most one rating that counts and at most one in progress.
create unique index rating_revisions_one_active on public.rating_revisions (visit_id) where state = 'active';
create unique index rating_revisions_one_draft on public.rating_revisions (visit_id) where state = 'draft';
create index rating_revisions_version_idx on public.rating_revisions (system_version_id) where state = 'active';

create table public.criterion_scores (
  revision_id uuid not null references public.rating_revisions (id) on delete cascade,
  criterion_id uuid not null references public.ranking_criteria (id),
  score smallint not null check (score >= 0),
  primary key (revision_id, criterion_id)
);

create table public.visit_photos (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid not null references public.visits (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  storage_path text not null unique,
  created_at timestamptz not null default now()
);
create index visit_photos_visit_idx on public.visit_photos (visit_id);

-- ---------------------------------------------------------------------------------------
-- Integrity triggers
-- ---------------------------------------------------------------------------------------

-- Published definitions never change. (Deleting an unused personal system still cascades.)
create function app_private.reject_change() returns trigger
language plpgsql as $$
begin
  raise exception '% rows are immutable once published', tg_table_name using errcode = '23514';
end;
$$;

create trigger ranking_system_versions_immutable before update on public.ranking_system_versions
  for each row execute function app_private.reject_change();
create trigger ranking_criteria_immutable before update on public.ranking_criteria
  for each row execute function app_private.reject_change();
create trigger criterion_score_levels_immutable before update on public.criterion_score_levels
  for each row execute function app_private.reject_change();

-- A version is only valid if its criteria total exactly 10 and every selectable score,
-- 0..max, has a description. Checked at commit so a version can be inserted row by row.
create function app_private.assert_version_valid(p_version_id uuid) returns void
language plpgsql set search_path = '' as $$
declare
  v_total integer;
  v_bad integer;
begin
  select coalesce(sum(max_points), 0) into v_total
  from public.ranking_criteria where version_id = p_version_id;
  if v_total <> 10 then
    raise exception 'criterion maximums must total exactly 10 (found %)', v_total using errcode = '23514';
  end if;

  select count(*) into v_bad
  from public.ranking_criteria c
  where c.version_id = p_version_id
    and (
      (select count(*) from public.criterion_score_levels l where l.criterion_id = c.id) <> c.max_points + 1
      or exists (select 1 from public.criterion_score_levels l where l.criterion_id = c.id and l.points > c.max_points)
    );
  if v_bad > 0 then
    raise exception 'every criterion needs a description for each score from 0 to its maximum' using errcode = '23514';
  end if;
end;
$$;

create function app_private.check_version_on_commit() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Skip when the version was removed again in the same transaction.
  if exists (select 1 from public.ranking_system_versions where id = new.id) then
    perform app_private.assert_version_valid(new.id);
  end if;
  return null;
end;
$$;

create constraint trigger ranking_system_versions_valid
  after insert on public.ranking_system_versions
  deferrable initially deferred
  for each row execute function app_private.check_version_on_commit();

-- Definitions cannot be extended after the fact either.
create function app_private.reject_late_definition_rows() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_version_id uuid;
  v_published timestamptz;
begin
  if tg_table_name = 'ranking_criteria' then
    v_version_id := new.version_id;
  else
    select version_id into v_version_id from public.ranking_criteria where id = new.criterion_id;
  end if;
  select published_at into v_published from public.ranking_system_versions where id = v_version_id;
  -- Rows may only be added in the transaction that created the version.
  if v_published is not null and v_published <> transaction_timestamp() then
    raise exception 'a published version cannot gain criteria or score levels' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger ranking_criteria_no_late_rows before insert on public.ranking_criteria
  for each row execute function app_private.reject_late_definition_rows();
create trigger criterion_score_levels_no_late_rows before insert on public.criterion_score_levels
  for each row execute function app_private.reject_late_definition_rows();

-- Scores must belong to the revision's own system version and sit inside 0..max.
-- Scores of a completed revision are frozen.
create function app_private.check_criterion_score() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_state public.revision_state;
  v_version uuid;
  v_max smallint;
  v_criterion_version uuid;
  v_revision_id uuid;
begin
  if tg_op = 'DELETE' then
    v_revision_id := old.revision_id;
  else
    v_revision_id := new.revision_id;
  end if;
  select state, system_version_id into v_state, v_version
  from public.rating_revisions where id = v_revision_id;

  if not found then
    -- The parent revision is being deleted; this row is going with it.
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if v_state <> 'draft' then
    raise exception 'scores of a completed rating cannot be changed; add a new revision instead' using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;

  select max_points, version_id into v_max, v_criterion_version
  from public.ranking_criteria where id = new.criterion_id;
  if v_criterion_version is distinct from v_version then
    raise exception 'criterion does not belong to the ranking system version of this rating' using errcode = '23514';
  end if;
  if new.score > v_max then
    raise exception 'score % is outside the allowed range 0..%', new.score, v_max using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger criterion_scores_check before insert or update or delete on public.criterion_scores
  for each row execute function app_private.check_criterion_score();

-- Completing a revision: every criterion must be answered, and the total is computed here
-- from the stored scores, overwriting anything the writer supplied.
create function app_private.check_rating_revision() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_expected integer;
  v_answered integer;
  v_total integer;
begin
  if tg_op = 'UPDATE' then
    if old.state = 'superseded' then
      raise exception 'a superseded rating is history and cannot be changed' using errcode = '23514';
    end if;
    if old.state = 'active' and not (
         new.state = 'superseded'
         and new.total = old.total
         and new.system_version_id = old.system_version_id
         and new.visit_id = old.visit_id
         and new.completed_at = old.completed_at) then
      raise exception 'a completed rating can only be superseded, not edited' using errcode = '23514';
    end if;
    if new.visit_id <> old.visit_id or new.user_id <> old.user_id then
      raise exception 'a rating cannot be moved to another visit' using errcode = '23514';
    end if;
  end if;

  if new.state = 'active' and (tg_op = 'INSERT' or old.state = 'draft') then
    select count(*) into v_expected from public.ranking_criteria where version_id = new.system_version_id;
    select count(*), coalesce(sum(score), 0) into v_answered, v_total
    from public.criterion_scores where revision_id = new.id;
    if v_answered <> v_expected then
      raise exception 'all % criteria must be scored before a rating is submitted (% answered)', v_expected, v_answered
        using errcode = '23514';
    end if;
    new.total := v_total;
    new.completed_at := coalesce(new.completed_at, now());
  end if;
  return new;
end;
$$;

create trigger rating_revisions_check before insert or update on public.rating_revisions
  for each row execute function app_private.check_rating_revision();

-- The owner recorded on a revision or photo always matches the visit's owner.
create function app_private.copy_visit_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  select user_id into strict new.user_id from public.visits where id = new.visit_id;
  return new;
end;
$$;

create trigger rating_revisions_owner before insert on public.rating_revisions
  for each row execute function app_private.copy_visit_owner();
create trigger visit_photos_owner before insert on public.visit_photos
  for each row execute function app_private.copy_visit_owner();

create function app_private.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger visits_touch before update on public.visits
  for each row execute function app_private.touch_updated_at();
create trigger ranking_systems_touch before update on public.ranking_systems
  for each row execute function app_private.touch_updated_at();

-- A visit cannot be handed to another person or moved to another restaurant's history
-- by its owner changing the user.
create function app_private.lock_visit_owner() returns trigger
language plpgsql as $$
begin
  if new.user_id <> old.user_id then
    raise exception 'a visit cannot change owner' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger visits_lock_owner before update on public.visits
  for each row execute function app_private.lock_visit_owner();

-- New accounts get a profile with a placeholder username the person can change.
create function app_private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    'user_' || substr(md5(new.id::text), 1, 16),
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''), 'New member')
  );
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function app_private.handle_new_user();
