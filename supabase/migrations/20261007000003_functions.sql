-- Deconstructed: the write paths that need validation, and community aggregation.
-- Every function re-checks ownership itself because it runs with elevated rights.

-- ---------------------------------------------------------------------------------------
-- Restaurants
-- ---------------------------------------------------------------------------------------

create function public.ensure_restaurant(
  p_provider text, p_place_id text, p_lat double precision default null, p_lng double precision default null
) returns public.restaurants
language plpgsql security definer set search_path = '' as $$
declare
  v_row public.restaurants;
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;

  insert into public.restaurants (provider, provider_place_id)
  values (p_provider, p_place_id)
  on conflict (provider, provider_place_id) do nothing;

  if p_lat is not null and p_lng is not null then
    update public.restaurants
    set lat = p_lat, lng = p_lng, location_cached_at = now()
    where provider = p_provider and provider_place_id = p_place_id;
  end if;

  select * into v_row from public.restaurants where provider = p_provider and provider_place_id = p_place_id;
  return v_row;
end;
$$;

create function public.cache_restaurant_location(p_restaurant_id uuid, p_lat double precision, p_lng double precision)
returns public.restaurants
language plpgsql security definer set search_path = '' as $$
declare
  v_row public.restaurants;
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;
  update public.restaurants
  set lat = p_lat, lng = p_lng, location_cached_at = now()
  where id = p_restaurant_id
  returning * into v_row;
  if not found then
    raise exception 'restaurant not found' using errcode = 'P0002';
  end if;
  return v_row;
end;
$$;

-- Provider terms allow a coordinate to be cached for at most 30 consecutive days.
create function app_private.purge_stale_restaurant_locations() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  update public.restaurants
  set lat = null, lng = null, location_cached_at = null
  where location_cached_at < now() - interval '30 days';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('purge-stale-restaurant-locations', '17 3 * * *',
                          'select app_private.purge_stale_restaurant_locations()');
  else
    raise notice 'pg_cron is not enabled: enable it and schedule app_private.purge_stale_restaurant_locations() daily (see README).';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------------------
-- Ranking systems
-- ---------------------------------------------------------------------------------------

-- A version's content in canonical form, without IDs, used to tell whether an edit actually
-- changed the rubric.
create function app_private.version_definition(p_version_id uuid) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'name', c.name,
      'guidance', c.guidance,
      'max_points', c.max_points,
      'levels', (
        select jsonb_agg(jsonb_build_object('points', l.points, 'label', l.label, 'description', l.description)
                         order by l.points)
        from public.criterion_score_levels l where l.criterion_id = c.id)
    ) order by c.position), '[]'::jsonb)
  from public.ranking_criteria c
  where c.version_id = p_version_id;
$$;

-- Publishes a personal system. Renaming alone keeps the current version; any change to the
-- criteria creates the next immutable version. Returns the current version's ID.
--
-- p_criteria: [{ "name", "guidance", "max_points", "levels": [{ "points", "label", "description" }] }]
create function public.publish_system_version(
  p_system_id uuid, p_name text, p_description text, p_criteria jsonb
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_system public.ranking_systems;
  v_normalized jsonb;
  v_total integer;
  v_version_id uuid;
  v_number integer;
  v_criterion jsonb;
  v_criterion_id uuid;
  v_position integer := 0;
  v_max integer;
begin
  select * into v_system from public.ranking_systems where id = p_system_id for update;
  if not found then
    raise exception 'ranking system not found' using errcode = 'P0002';
  end if;
  if v_system.owner_id is distinct from (select auth.uid()) then
    raise exception 'you can only change ranking systems you own' using errcode = '42501';
  end if;
  if v_system.is_archived then
    raise exception 'restore this system from the archive before changing it' using errcode = '23514';
  end if;
  if jsonb_typeof(p_criteria) is distinct from 'array' or jsonb_array_length(p_criteria) = 0 then
    raise exception 'a ranking system needs at least one criterion' using errcode = '23514';
  end if;

  -- Validate shape and build the canonical form in one pass.
  select coalesce(sum((c ->> 'max_points')::integer), 0),
         jsonb_agg(jsonb_build_object(
           'name', btrim(c ->> 'name'),
           'guidance', btrim(coalesce(c ->> 'guidance', '')),
           'max_points', (c ->> 'max_points')::integer,
           'levels', (
             select jsonb_agg(jsonb_build_object(
                      'points', (l ->> 'points')::integer,
                      'label', btrim(coalesce(l ->> 'label', '')),
                      'description', btrim(coalesce(l ->> 'description', '')))
                    order by (l ->> 'points')::integer)
             from jsonb_array_elements(coalesce(c -> 'levels', '[]'::jsonb)) l)
         ) order by ord)
  into v_total, v_normalized
  from jsonb_array_elements(p_criteria) with ordinality as t(c, ord);

  if v_total <> 10 then
    raise exception 'criterion maximums must total exactly 10 (found %)', v_total using errcode = '23514';
  end if;

  for v_criterion in select * from jsonb_array_elements(v_normalized) loop
    v_max := (v_criterion ->> 'max_points')::integer;
    if v_max < 1 then
      raise exception 'each criterion needs a maximum of at least 1 point' using errcode = '23514';
    end if;
    if (v_criterion ->> 'name') = '' then
      raise exception 'every criterion needs a name' using errcode = '23514';
    end if;
    -- Exactly one described level for each score 0..max.
    if (select array_agg((l ->> 'points')::integer order by (l ->> 'points')::integer)
        from jsonb_array_elements(coalesce(v_criterion -> 'levels', '[]'::jsonb)) l)
       is distinct from (select array_agg(g) from generate_series(0, v_max) g) then
      raise exception 'criterion "%" needs a description for every score from 0 to %', v_criterion ->> 'name', v_max
        using errcode = '23514';
    end if;
    if exists (select 1 from jsonb_array_elements(v_criterion -> 'levels') l where (l ->> 'description') = '') then
      raise exception 'criterion "%" has a score without a description', v_criterion ->> 'name' using errcode = '23514';
    end if;
  end loop;

  if v_system.current_version_id is null
     or app_private.version_definition(v_system.current_version_id) <> v_normalized then
    select coalesce(max(version_number), 0) + 1 into v_number
    from public.ranking_system_versions where system_id = p_system_id;

    insert into public.ranking_system_versions (system_id, version_number)
    values (p_system_id, v_number)
    returning id into v_version_id;

    for v_criterion in select * from jsonb_array_elements(v_normalized) loop
      insert into public.ranking_criteria (version_id, position, name, guidance, max_points)
      values (v_version_id, v_position, v_criterion ->> 'name', v_criterion ->> 'guidance',
              (v_criterion ->> 'max_points')::smallint)
      returning id into v_criterion_id;

      insert into public.criterion_score_levels (criterion_id, points, label, description)
      select v_criterion_id, (l ->> 'points')::smallint, l ->> 'label', l ->> 'description'
      from jsonb_array_elements(v_criterion -> 'levels') l;

      v_position := v_position + 1;
    end loop;

    perform app_private.assert_version_valid(v_version_id);
  else
    v_version_id := v_system.current_version_id;
  end if;

  update public.ranking_systems
  set name = btrim(p_name), description = btrim(coalesce(p_description, '')), current_version_id = v_version_id
  where id = p_system_id;

  delete from public.ranking_system_drafts where system_id = p_system_id;
  return v_version_id;
end;
$$;

-- ---------------------------------------------------------------------------------------
-- Ratings
-- ---------------------------------------------------------------------------------------

-- Saves a draft or submits a completed rating for one of the caller's visits.
--
-- p_scores: { "<criterion id>": <integer>, ... }. There is no total parameter: the total is
-- summed from the stored scores by the rating_revisions trigger.
--
-- Submitting never edits an earlier completed rating. It adds a revision and marks the
-- previous one superseded, so history is kept and only the newest counts.
create function public.save_rating(
  p_visit_id uuid, p_system_version_id uuid, p_scores jsonb, p_complete boolean
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_visit public.visits;
  v_system public.ranking_systems;
  v_active public.rating_revisions;
  v_draft public.rating_revisions;
  v_revision_id uuid;
  v_archived boolean;
  v_unknown integer;
begin
  select * into v_visit from public.visits where id = p_visit_id for update;
  if not found or v_visit.user_id is distinct from v_uid then
    raise exception 'you can only rate your own visits' using errcode = '42501';
  end if;

  select s.* into v_system
  from public.ranking_system_versions sv join public.ranking_systems s on s.id = sv.system_id
  where sv.id = p_system_version_id;
  if not found then
    raise exception 'ranking system version not found' using errcode = 'P0002';
  end if;
  if v_system.owner_id is not null and v_system.owner_id <> v_uid then
    raise exception 'you can only rate with the standard systems or your own' using errcode = '42501';
  end if;

  select * into v_active from public.rating_revisions where visit_id = p_visit_id and state = 'active';
  select * into v_draft from public.rating_revisions where visit_id = p_visit_id and state = 'draft';

  -- Carrying on with the version a rating already uses is always allowed. Anything else is
  -- a fresh choice and must be the latest version of a system that is not archived.
  if p_system_version_id is distinct from v_active.system_version_id
     and p_system_version_id is distinct from v_draft.system_version_id then
    v_archived := v_system.is_archived or exists (
      select 1 from public.profiles p
      where p.id = v_uid and v_system.id = any (p.archived_standard_system_ids));
    if v_archived then
      raise exception 'this ranking system is archived and cannot be used for new ratings' using errcode = '23514';
    end if;
    if v_system.current_version_id is distinct from p_system_version_id then
      raise exception 'new ratings must use the latest version of the ranking system' using errcode = '23514';
    end if;
  end if;

  if jsonb_typeof(coalesce(p_scores, '{}'::jsonb)) <> 'object' then
    raise exception 'scores must be an object of criterion id to points' using errcode = '22023';
  end if;
  -- UUID keys are compared as lower-case text from here on.
  select coalesce(jsonb_object_agg(lower(key), value), '{}'::jsonb) into p_scores
  from jsonb_each(coalesce(p_scores, '{}'::jsonb));

  select count(*) into v_unknown
  from jsonb_each(coalesce(p_scores, '{}'::jsonb)) s
  where not exists (
    select 1 from public.ranking_criteria c
    where c.version_id = p_system_version_id and c.id::text = s.key);
  if v_unknown > 0 then
    raise exception 'a score was given for a criterion that is not part of this system version' using errcode = '23514';
  end if;

  -- Submitting the same scores again changes nothing and adds no history.
  if p_complete and v_active.id is not null and v_active.system_version_id = p_system_version_id
     and not exists (
       select 1
       from public.ranking_criteria c
       left join public.criterion_scores cs on cs.criterion_id = c.id and cs.revision_id = v_active.id
       where c.version_id = p_system_version_id
         and cs.score is distinct from (p_scores ->> c.id::text)::smallint) then
    delete from public.rating_revisions where id = v_draft.id;
    return v_active.id;
  end if;

  -- Rebuild the working revision from the supplied scores. Range and membership are
  -- enforced by the criterion_scores trigger.
  delete from public.rating_revisions where id = v_draft.id;
  insert into public.rating_revisions (visit_id, user_id, system_version_id, state)
  values (p_visit_id, v_uid, p_system_version_id, 'draft')
  returning id into v_revision_id;

  insert into public.criterion_scores (revision_id, criterion_id, score)
  select v_revision_id, c.id, (p_scores ->> c.id::text)::smallint
  from public.ranking_criteria c
  where c.version_id = p_system_version_id and p_scores ? c.id::text;

  if p_complete then
    update public.rating_revisions set state = 'superseded' where id = v_active.id;
    -- The trigger refuses this unless every criterion is answered, and sets the total.
    update public.rating_revisions set state = 'active' where id = v_revision_id;
  end if;

  update public.visits set updated_at = now() where id = p_visit_id;
  return v_revision_id;
end;
$$;

create function public.discard_draft_rating(p_visit_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.rating_revisions r
  using public.visits v
  where r.visit_id = v.id and v.id = p_visit_id and v.user_id = (select auth.uid()) and r.state = 'draft';
end;
$$;

-- ---------------------------------------------------------------------------------------
-- Community scores
-- ---------------------------------------------------------------------------------------

-- One row per standard system version that has public ratings for the restaurant.
--   * Only standard systems (owner_id is null). A user's edited copy is a different system
--     and is never folded into the original's average.
--   * Versions are never mixed: the grouping key is the version.
--   * Each person counts once per version, through their most recent completed visit.
--   * Only public reviews count. Followers-only and private reviews are excluded.
create function public.community_scores(p_provider text, p_place_id text)
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

-- ---------------------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon;
revoke execute on all functions in schema app_private from public, anon;
grant execute on function
  public.ensure_restaurant(text, text, double precision, double precision),
  public.cache_restaurant_location(uuid, double precision, double precision),
  public.publish_system_version(uuid, text, text, jsonb),
  public.save_rating(uuid, uuid, jsonb, boolean),
  public.discard_draft_rating(uuid),
  public.community_scores(text, text)
to authenticated;
