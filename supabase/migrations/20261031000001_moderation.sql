-- Deconstructed: blocking, reporting, text filtering, bans and acceptance of the terms.
--
-- Design notes
--   * Blocking and bans are enforced here, in row-level security, so they hold for anyone
--     calling the API directly. The app only reflects them.
--   * A report keeps a snapshot of what was reported. Deleting the content afterwards does
--     not erase the evidence, and the moderator can read it whatever its visibility.
--   * Community scores are anonymous averages, so a block does not change them. A ban does.
--   * docs/moderation.md is the runbook for acting on reports.

-- ---------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------

-- Set only through accept_terms(). The column is left out of the client's update grant.
alter table public.profiles add column terms_accepted_at timestamptz;

create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index blocks_blocked_idx on public.blocks (blocked_id);

-- Added by hand: insert into app_private.moderators values ('<auth user id>');
create table app_private.moderators (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table app_private.banned_users (
  user_id uuid primary key references auth.users (id) on delete cascade,
  banned_at timestamptz not null default now()
);

create type public.report_target as enum ('visit', 'photo', 'user');
create type public.report_reason as enum ('spam', 'harassment', 'hate', 'sexual', 'violence', 'other');
create type public.report_status as enum ('open', 'actioned', 'dismissed');

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references public.profiles (id) on delete set null,
  target_type public.report_target not null,
  -- No foreign keys on the target: a report outlives the content and the account it is about.
  target_id uuid not null,
  reported_user_id uuid not null,
  reason public.report_reason not null,
  details text not null default '' check (char_length(details) <= 1000),
  -- { username, display_name, notes, dishes, system_name, photo_paths }
  snapshot jsonb not null,
  status public.report_status not null default 'open',
  resolution text,
  resolved_by uuid references public.profiles (id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);
-- Reporting the same thing twice while it is still open adds nothing.
create unique index reports_one_open on public.reports (reporter_id, target_type, target_id) where status = 'open';
create index reports_open_idx on public.reports (created_at) where status = 'open';
create index reports_reporter_idx on public.reports (reporter_id, created_at desc);

-- ---------------------------------------------------------------------------------------
-- Text filter
-- ---------------------------------------------------------------------------------------

-- A starting list of slurs, sexual terms and threats, matched as whole words after
-- app_private.normalize_text(). Mild swearing is allowed on purpose: "the pasta was shit" is
-- a fair review. Add a row to extend it. It takes effect at once, and only checks new text.
create table app_private.blocked_terms (
  term text primary key check (term ~ '^[a-z]+( [a-z]+)*$')
);

insert into app_private.blocked_terms (term) values
  ('nigger'), ('niggers'), ('nigga'), ('niggas'),
  ('faggot'), ('fag'), ('fags'), ('dyke'), ('dykes'),
  ('tranny'), ('trannies'), ('retard'), ('retards'),
  ('kike'), ('kikes'), ('spic'), ('spics'), ('chink'), ('chinks'),
  ('gook'), ('gooks'), ('wetback'), ('wetbacks'), ('coon'), ('coons'),
  ('paki'), ('pakis'), ('raghead'), ('ragheads'), ('towelhead'), ('towelheads'),
  ('cunt'), ('cunts'), ('whore'), ('whores'),
  ('blowjob'), ('handjob'), ('cumshot'), ('gangbang'), ('rapist'),
  ('child porn'), ('kiddie porn'), ('cp links'),
  ('kill yourself'), ('kill urself'), ('kys'), ('go die'), ('hang yourself'),
  ('i will kill you'), ('i will rape you'), ('rape you'), ('gas the jews'),
  ('heil hitler'), ('white power');

-- Lower-cases, undoes common letter swaps and reduces everything else to single spaces, so
-- "K1LL   y0urs3lf!!" and "kill_yourself" both read "kill yourself".
create function app_private.normalize_text(p_text text) returns text
language sql immutable set search_path = '' as $$
  select btrim(regexp_replace(translate(lower(coalesce(p_text, '')), '0134578@$', 'oieastbas'), '[^a-z]+', ' ', 'g'));
$$;

-- A whole-word pattern that allows stretched letters: "kill" becomes k+i+l{2,}, which matches
-- "kiiilll" but keeps a double letter double, so "coon" never matches "con".
create function app_private.term_pattern(p_term text) returns text
language sql immutable set search_path = '' as $$
  select '\m' || regexp_replace(regexp_replace(p_term, '([a-z])', '\1+', 'g'), '([a-z])\+\1\+', '\1{2,}', 'g') || '\M';
$$;

create function app_private.contains_blocked_term(p_text text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from app_private.blocked_terms t
    where app_private.normalize_text(p_text) ~ app_private.term_pattern(t.term)
  );
$$;

-- Checks the columns named in the trigger's arguments. Only changed text is checked, so
-- someone whose old text matches a newer term can still change their other settings.
create function app_private.reject_blocked_text() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_new jsonb := to_jsonb(new);
  v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end;
  v_column text;
begin
  foreach v_column in array tg_argv loop
    if (v_new -> v_column) is distinct from (v_old -> v_column)
       and app_private.contains_blocked_term(v_new ->> v_column) then
      raise exception 'that wording isn''t allowed under the community rules. Please change it' using errcode = '23514';
    end if;
  end loop;
  return new;
end;
$$;

create trigger profiles_filter before insert or update on public.profiles
  for each row execute function app_private.reject_blocked_text('username', 'display_name');
create trigger visits_filter before insert or update on public.visits
  for each row execute function app_private.reject_blocked_text('notes', 'dishes');
create trigger ranking_systems_filter before insert or update on public.ranking_systems
  for each row execute function app_private.reject_blocked_text('name', 'description');
create trigger ranking_criteria_filter before insert on public.ranking_criteria
  for each row execute function app_private.reject_blocked_text('name', 'guidance');
create trigger criterion_score_levels_filter before insert on public.criterion_score_levels
  for each row execute function app_private.reject_blocked_text('label', 'description');

-- A name from the sign-in provider must never stop an account being created.
create or replace function app_private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_name text := nullif(btrim(new.raw_user_meta_data ->> 'full_name'), '');
begin
  if app_private.contains_blocked_term(v_name) then
    v_name := null;
  end if;
  insert into public.profiles (id, username, display_name)
  values (new.id, 'user_' || substr(md5(new.id::text), 1, 16), coalesce(v_name, 'New member'));
  return new;
end;
$$;

-- ---------------------------------------------------------------------------------------
-- Predicates
-- ---------------------------------------------------------------------------------------

create function app_private.is_blocked_with(p_other uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = (select auth.uid()) and blocked_id = p_other)
       or (blocker_id = p_other and blocked_id = (select auth.uid()))
  );
$$;

create function app_private.is_banned(p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from app_private.banned_users where user_id = p_user);
$$;

create function app_private.is_moderator() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from app_private.moderators where user_id = (select auth.uid()));
$$;

-- False when a block in either direction or a ban stands between the caller and this person.
create function app_private.can_see_person(p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_user = (select auth.uid())
      or not (app_private.is_blocked_with(p_user) or app_private.is_banned(p_user));
$$;

create function app_private.has_accepted_terms() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles where id = (select auth.uid()) and terms_accepted_at is not null
  );
$$;

-- Moderators read the photos named in an open report, whatever the review's visibility.
create function app_private.moderator_can_read_photo(p_path text) returns boolean
language sql stable security definer set search_path = '' as $$
  select app_private.is_moderator() and exists (
    select 1 from public.reports r
    where r.status = 'open' and r.snapshot -> 'photo_paths' ? p_path
  );
$$;

-- The single rule every review read goes through, so reviews, ratings, photos and the custom
-- systems behind them all disappear together.
create or replace function app_private.can_view_visit(p_visit_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.visits v
    where v.id = p_visit_id
      and (
        v.user_id = (select auth.uid())
        or (
          app_private.can_see_person(v.user_id)
          and exists (select 1 from public.rating_revisions r where r.visit_id = v.id and r.state = 'active')
          and (
            v.visibility = 'public'
            or (v.visibility = 'followers' and app_private.is_following(v.user_id))
          )
        )
      )
  );
$$;

-- ---------------------------------------------------------------------------------------
-- Blocks end any follow between the two people
-- ---------------------------------------------------------------------------------------

create function app_private.remove_follows_on_block() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.follows
  where (follower_id = new.blocker_id and followee_id = new.blocked_id)
     or (follower_id = new.blocked_id and followee_id = new.blocker_id);
  return null;
end;
$$;

create trigger blocks_remove_follows after insert on public.blocks
  for each row execute function app_private.remove_follows_on_block();

-- ---------------------------------------------------------------------------------------
-- Privileges and policies
-- ---------------------------------------------------------------------------------------

-- Reports are written through report_content() and read only by moderators.
grant select, insert, delete on public.blocks to authenticated;
grant select on public.reports to authenticated;

alter table public.blocks enable row level security;
alter table public.reports enable row level security;
alter table app_private.moderators enable row level security;
alter table app_private.banned_users enable row level security;
alter table app_private.blocked_terms enable row level security;

-- Only the person who blocked can see the block; the other person is never told.
create policy blocks_own on public.blocks for all to authenticated
  using (blocker_id = (select auth.uid())) with check (blocker_id = (select auth.uid()));

create policy reports_moderator_read on public.reports for select to authenticated
  using (app_private.is_moderator());

drop policy profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated
  using (app_private.can_see_person(id));

drop policy follows_insert on public.follows;
create policy follows_insert on public.follows for insert to authenticated
  with check (follower_id = (select auth.uid()) and app_private.can_see_person(followee_id));

drop policy visits_insert on public.visits;
create policy visits_insert on public.visits for insert to authenticated
  with check (user_id = (select auth.uid()) and app_private.has_accepted_terms());

drop policy visit_photos_objects_read on storage.objects;
create policy visit_photos_objects_read on storage.objects for select to authenticated
  using (
    bucket_id = 'visit-photos'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or exists (
        select 1 from public.visit_photos p
        where p.storage_path = name and app_private.can_view_visit(p.visit_id)
      )
      or app_private.moderator_can_read_photo(name)
    )
  );

-- ---------------------------------------------------------------------------------------
-- Functions for everyone
-- ---------------------------------------------------------------------------------------

create function public.accept_terms() returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.profiles
  set terms_accepted_at = coalesce(terms_accepted_at, now())
  where id = (select auth.uid());
end;
$$;

-- The people the caller has blocked. Profiles of blocked people are otherwise hidden from
-- the caller, and this is what lets them be unblocked.
create function public.blocked_users() returns setof public.profiles
language sql stable security definer set search_path = '' as $$
  select p.*
  from public.blocks b join public.profiles p on p.id = b.blocked_id
  where b.blocker_id = (select auth.uid())
  order by p.display_name;
$$;

create function public.is_moderator() returns boolean
language sql stable security definer set search_path = '' as $$
  select app_private.is_moderator();
$$;

-- Files a report on a review, a photo or a person. Reviews and photos must be ones the caller
-- can read. A person can be reported even when a block hides them, including by the blocker.
create function public.report_content(
  p_target_type public.report_target, p_target_id uuid, p_reason public.report_reason, p_details text default ''
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_user_id uuid;
  v_snapshot jsonb := '{}'::jsonb;
  v_profile public.profiles;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;
  if (select count(*) from public.reports
      where reporter_id = v_uid and created_at > now() - interval '1 day') >= 50 then
    raise exception 'you have sent a lot of reports today. Try again tomorrow' using errcode = '23514';
  end if;

  if p_target_type = 'visit' then
    select v.user_id,
           jsonb_build_object(
             'notes', v.notes,
             'dishes', to_jsonb(v.dishes),
             'system_name', (
               select s.name
               from public.rating_revisions r
               join public.ranking_system_versions sv on sv.id = r.system_version_id
               join public.ranking_systems s on s.id = sv.system_id
               where r.visit_id = v.id and r.state = 'active'),
             'photo_paths', coalesce((
               select jsonb_agg(p.storage_path) from public.visit_photos p where p.visit_id = v.id), '[]'::jsonb))
    into v_user_id, v_snapshot
    from public.visits v
    where v.id = p_target_id and app_private.can_view_visit(v.id);
  elsif p_target_type = 'photo' then
    select p.user_id, jsonb_build_object('photo_paths', jsonb_build_array(p.storage_path))
    into v_user_id, v_snapshot
    from public.visit_photos p
    where p.id = p_target_id and app_private.can_view_visit(p.visit_id);
  else
    v_user_id := (select id from public.profiles where id = p_target_id);
  end if;

  if v_user_id is null then
    raise exception 'that item no longer exists' using errcode = 'P0002';
  end if;
  if v_user_id = v_uid then
    raise exception 'you can''t report yourself' using errcode = '23514';
  end if;

  select * into v_profile from public.profiles where id = v_user_id;
  v_snapshot := v_snapshot || jsonb_build_object('username', v_profile.username, 'display_name', v_profile.display_name);

  insert into public.reports (reporter_id, target_type, target_id, reported_user_id, reason, details, snapshot)
  values (v_uid, p_target_type, p_target_id, v_user_id, p_reason, left(btrim(coalesce(p_details, '')), 1000), v_snapshot)
  on conflict (reporter_id, target_type, target_id) where status = 'open' do nothing;
end;
$$;

-- ---------------------------------------------------------------------------------------
-- Functions for moderators
-- ---------------------------------------------------------------------------------------

-- Applies a moderator's decision to the database. Storage and Auth can't be changed from SQL,
-- so this returns what the `moderate` Edge Function must still do, and the report stays open
-- until finish_report(). A failed step can therefore be retried from the queue.
--
-- Returns { storage_paths: [...], ban_user_id, delete_user_id }.
create function public.moderate_report(p_report_id uuid, p_action text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_report public.reports;
  v_paths jsonb := '[]'::jsonb;
  v_account uuid;
begin
  if not app_private.is_moderator() then
    raise exception 'only moderators can do this' using errcode = '42501';
  end if;
  select * into v_report from public.reports where id = p_report_id and status = 'open' for update;
  if not found then
    raise exception 'that report is no longer open' using errcode = 'P0002';
  end if;
  select id into v_account from auth.users where id = v_report.reported_user_id;

  if p_action = 'dismiss' then
    null;
  elsif p_action = 'remove_content' then
    v_paths := coalesce(v_report.snapshot -> 'photo_paths', '[]'::jsonb);
    if v_report.target_type = 'visit' then
      v_paths := v_paths || coalesce((
        select jsonb_agg(storage_path) from public.visit_photos where visit_id = v_report.target_id), '[]'::jsonb);
      delete from public.visits where id = v_report.target_id;
    elsif v_report.target_type = 'photo' then
      delete from public.visit_photos where id = v_report.target_id;
    else
      -- For a person, the content is their names.
      update public.profiles
      set username = 'user_' || substr(md5(id::text), 1, 16), display_name = 'New member'
      where id = v_report.target_id;
    end if;
  elsif p_action = 'ban' then
    if v_account = (select auth.uid()) then
      raise exception 'you can''t ban yourself' using errcode = '23514';
    end if;
    if v_account is not null then
      insert into app_private.banned_users (user_id) values (v_account) on conflict do nothing;
      -- Lists embed the other person's profile, which a ban hides.
      delete from public.follows where follower_id = v_account or followee_id = v_account;
    end if;
    return jsonb_build_object('storage_paths', '[]'::jsonb, 'ban_user_id', v_account);
  elsif p_action = 'delete_account' then
    if v_account = (select auth.uid()) then
      raise exception 'you can''t delete your own account from a report' using errcode = '23514';
    end if;
    return jsonb_build_object('storage_paths', '[]'::jsonb, 'delete_user_id', v_account);
  else
    raise exception 'unknown moderation action' using errcode = '22023';
  end if;

  return jsonb_build_object('storage_paths', v_paths);
end;
$$;

-- Closes the report and every other open report it settles: those on the same item, and for
-- a ban or a deleted account, everything open against that person.
create function public.finish_report(p_report_id uuid, p_action text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_report public.reports;
begin
  if not app_private.is_moderator() then
    raise exception 'only moderators can do this' using errcode = '42501';
  end if;
  select * into v_report from public.reports where id = p_report_id;
  if not found then
    raise exception 'that report no longer exists' using errcode = 'P0002';
  end if;

  update public.reports
  set status = (case when p_action = 'dismiss' then 'dismissed' else 'actioned' end)::public.report_status,
      resolution = p_action,
      resolved_by = (select auth.uid()),
      resolved_at = now()
  where status = 'open'
    and (
      (target_type = v_report.target_type and target_id = v_report.target_id)
      or (p_action in ('ban', 'delete_account') and reported_user_id = v_report.reported_user_id)
    );
end;
$$;

-- ---------------------------------------------------------------------------------------
-- Community scores no longer count banned people
-- ---------------------------------------------------------------------------------------

create or replace function public.community_scores(p_provider text, p_place_id text)
returns table (
  system_id uuid,
  system_name text,
  version_id uuid,
  version_number integer,
  user_count integer,
  average numeric,
  criteria jsonb
)
language sql stable security definer set search_path = '' as $$
  with latest as (
    select distinct on (v.user_id, r.system_version_id)
           v.user_id, r.id as revision_id, r.system_version_id, r.total
    from public.restaurants rest
    join public.visits v on v.restaurant_id = rest.id
    join public.rating_revisions r on r.visit_id = v.id and r.state = 'active'
    join public.ranking_system_versions sv on sv.id = r.system_version_id
    join public.ranking_systems s on s.id = sv.system_id
    where rest.provider = p_provider
      and rest.provider_place_id = p_place_id
      and v.visibility = 'public'
      and s.owner_id is null
      and not app_private.is_banned(v.user_id)
    order by v.user_id, r.system_version_id, v.visited_on desc, v.created_at desc
  )
  select s.id,
         s.name,
         sv.id,
         sv.version_number,
         count(*)::integer,
         round(avg(l.total), 1),
         (
           select jsonb_agg(jsonb_build_object(
                    'criterion_id', c.id,
                    'average', (
                      select round(avg(cs.score), 2)
                      from latest l2
                      join public.criterion_scores cs on cs.revision_id = l2.revision_id and cs.criterion_id = c.id
                      where l2.system_version_id = sv.id))
                  order by c.position)
           from public.ranking_criteria c
           where c.version_id = sv.id
         )
  from latest l
  join public.ranking_system_versions sv on sv.id = l.system_version_id
  join public.ranking_systems s on s.id = sv.system_id
  group by s.id, s.name, sv.id, sv.version_number
  order by count(*) desc, s.name;
$$;

revoke execute on all functions in schema public from public, anon;
revoke execute on all functions in schema app_private from public, anon;
grant execute on function
  app_private.is_blocked_with(uuid),
  app_private.is_banned(uuid),
  app_private.is_moderator(),
  app_private.can_see_person(uuid),
  app_private.has_accepted_terms(),
  app_private.moderator_can_read_photo(text)
to authenticated;
grant execute on function
  public.accept_terms(),
  public.blocked_users(),
  public.is_moderator(),
  public.report_content(public.report_target, uuid, public.report_reason, text),
  public.moderate_report(uuid, text),
  public.finish_report(uuid, text)
to authenticated;
