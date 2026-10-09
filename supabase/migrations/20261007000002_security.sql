-- Deconstructed: row-level security.
--
-- Visibility rule, used everywhere a review can be read:
--   the author always can; anyone else only if the visit has a completed rating and it is
--   public, or it is followers-only and the reader follows the author.

-- Helper predicates run as their owner so policies can consult other tables without
-- tripping over those tables' own policies (and without recursing).

create function app_private.is_following(p_target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.follows
    where follower_id = (select auth.uid()) and followee_id = p_target
  );
$$;

create function app_private.can_view_visit(p_visit_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.visits v
    where v.id = p_visit_id
      and (
        v.user_id = (select auth.uid())
        or (
          exists (select 1 from public.rating_revisions r where r.visit_id = v.id and r.state = 'active')
          and (
            v.visibility = 'public'
            or (v.visibility = 'followers' and app_private.is_following(v.user_id))
          )
        )
      )
  );
$$;

create function app_private.can_view_revision(p_revision_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.rating_revisions r
    where r.id = p_revision_id
      and (
        r.user_id = (select auth.uid())
        -- Other people only ever see the rating that currently counts, never drafts or history.
        or (r.state = 'active' and app_private.can_view_visit(r.visit_id))
      )
  );
$$;

-- A system's definition is readable if it is standard, yours, or behind a review you can read.
create function app_private.can_view_system(p_system_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.ranking_systems s
    where s.id = p_system_id
      and (
        s.owner_id is null
        or s.owner_id = (select auth.uid())
        or exists (
          select 1
          from public.ranking_system_versions sv
          join public.rating_revisions r on r.system_version_id = sv.id and r.state = 'active'
          where sv.system_id = s.id and app_private.can_view_visit(r.visit_id)
        )
      )
  );
$$;

create function app_private.owns_visit(p_visit_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.visits where id = p_visit_id and user_id = (select auth.uid()));
$$;

revoke all on schema app_private from public, anon, authenticated;
grant usage on schema app_private to authenticated;
revoke execute on all functions in schema app_private from public, anon;
grant execute on function
  app_private.is_following(uuid),
  app_private.can_view_visit(uuid),
  app_private.can_view_revision(uuid),
  app_private.can_view_system(uuid),
  app_private.owns_visit(uuid)
to authenticated;

-- ---------------------------------------------------------------------------------------
-- Table privileges: start from nothing, grant only what the app uses.
-- ---------------------------------------------------------------------------------------

revoke all on all tables in schema public from anon, authenticated;

grant select on public.profiles to authenticated;
grant update (username, display_name, default_visibility, default_system_id, archived_standard_system_ids)
  on public.profiles to authenticated;

grant select, insert, delete on public.follows to authenticated;

grant select on public.restaurants to authenticated; -- written through ensure_restaurant()
grant select, insert, delete on public.saved_places to authenticated;

grant select, delete on public.ranking_systems to authenticated;
grant insert (id, owner_id, template_key, forked_from_system_id, name, description) on public.ranking_systems to authenticated;
-- current_version_id is deliberately absent: only publish_system_version() moves it.
grant update (name, description, is_archived) on public.ranking_systems to authenticated;
grant select, insert, update, delete on public.ranking_system_drafts to authenticated;

-- Definitions and ratings are read-only to clients; all writes go through functions.
grant select on public.ranking_system_versions, public.ranking_criteria, public.criterion_score_levels to authenticated;
grant select on public.rating_revisions, public.criterion_scores to authenticated;

grant select, insert, delete on public.visits to authenticated;
grant update (visited_on, notes, dishes, spend_per_person, currency_code, visibility) on public.visits to authenticated;
grant select, insert, delete on public.visit_photos to authenticated;

alter table public.profiles enable row level security;
alter table public.follows enable row level security;
alter table public.restaurants enable row level security;
alter table public.saved_places enable row level security;
alter table public.ranking_systems enable row level security;
alter table public.ranking_system_drafts enable row level security;
alter table public.ranking_system_versions enable row level security;
alter table public.ranking_criteria enable row level security;
alter table public.criterion_score_levels enable row level security;
alter table public.visits enable row level security;
alter table public.rating_revisions enable row level security;
alter table public.criterion_scores enable row level security;
alter table public.visit_photos enable row level security;

-- ---------------------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------------------

-- Profiles: names are discoverable so people can find each other. Only you edit yours.
create policy profiles_read on public.profiles for select to authenticated using (true);
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Follows: you see edges you are part of, create your own follows, and may remove either
-- a follow you made or a follower you no longer want.
create policy follows_read on public.follows for select to authenticated
  using (follower_id = (select auth.uid()) or followee_id = (select auth.uid()));
create policy follows_insert on public.follows for insert to authenticated
  with check (follower_id = (select auth.uid()));
create policy follows_delete on public.follows for delete to authenticated
  using (follower_id = (select auth.uid()) or followee_id = (select auth.uid()));

-- Restaurants hold no user content: a place ID and a short-lived coordinate.
create policy restaurants_read on public.restaurants for select to authenticated using (true);

create policy saved_places_own on public.saved_places for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Ranking systems: users can only create, edit and delete systems they own. Standard
-- systems (owner_id is null) match none of the write policies.
create policy ranking_systems_read on public.ranking_systems for select to authenticated
  using (owner_id is null or owner_id = (select auth.uid()) or app_private.can_view_system(id));
create policy ranking_systems_insert on public.ranking_systems for insert to authenticated
  with check (owner_id = (select auth.uid()));
create policy ranking_systems_update on public.ranking_systems for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy ranking_systems_delete on public.ranking_systems for delete to authenticated
  using (owner_id = (select auth.uid()));

create policy ranking_system_drafts_own on public.ranking_system_drafts for all to authenticated
  using (exists (select 1 from public.ranking_systems s where s.id = system_id and s.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.ranking_systems s where s.id = system_id and s.owner_id = (select auth.uid())));

create policy ranking_system_versions_read on public.ranking_system_versions for select to authenticated
  using (app_private.can_view_system(system_id));
create policy ranking_criteria_read on public.ranking_criteria for select to authenticated
  using (exists (
    select 1 from public.ranking_system_versions sv
    where sv.id = version_id and app_private.can_view_system(sv.system_id)));
create policy criterion_score_levels_read on public.criterion_score_levels for select to authenticated
  using (exists (
    select 1
    from public.ranking_criteria c
    join public.ranking_system_versions sv on sv.id = c.version_id
    where c.id = criterion_id and app_private.can_view_system(sv.system_id)));

-- Visits
create policy visits_read on public.visits for select to authenticated
  using (user_id = (select auth.uid()) or app_private.can_view_visit(id));
create policy visits_insert on public.visits for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy visits_update on public.visits for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy visits_delete on public.visits for delete to authenticated
  using (user_id = (select auth.uid()));

create policy rating_revisions_read on public.rating_revisions for select to authenticated
  using (user_id = (select auth.uid()) or (state = 'active' and app_private.can_view_visit(visit_id)));
create policy criterion_scores_read on public.criterion_scores for select to authenticated
  using (app_private.can_view_revision(revision_id));

create policy visit_photos_read on public.visit_photos for select to authenticated
  using (app_private.can_view_visit(visit_id));
create policy visit_photos_insert on public.visit_photos for insert to authenticated
  with check (app_private.owns_visit(visit_id));
create policy visit_photos_delete on public.visit_photos for delete to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------
-- Storage: user photos live in a private bucket under "<user id>/<visit id>/<file>".
-- ---------------------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('visit-photos', 'visit-photos', false, 5242880, array['image/jpeg', 'image/heic', 'image/png'])
on conflict (id) do nothing;

create policy visit_photos_objects_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'visit-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy visit_photos_objects_delete on storage.objects for delete to authenticated
  using (bucket_id = 'visit-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
-- A photo is readable exactly when the visit it belongs to is.
create policy visit_photos_objects_read on storage.objects for select to authenticated
  using (
    bucket_id = 'visit-photos'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or exists (
        select 1 from public.visit_photos p
        where p.storage_path = name and app_private.can_view_visit(p.visit_id)
      )
    )
  );
