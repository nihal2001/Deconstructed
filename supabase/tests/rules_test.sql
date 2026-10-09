-- End-to-end checks of the backend rules. Run with supabase/tests/run.sh.
-- Each statement commits on its own so deferred constraint checks fire as they would in use.
\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned

\set alice '''a0000000-0000-4000-8000-000000000001'''
\set bob   '''a0000000-0000-4000-8000-000000000002'''
\set general      '''00000000-0000-4000-a000-000000000001'''
\set general_v1   '''00000000-0000-4000-a001-000000000001'''
\set fast_v1      '''00000000-0000-4000-a001-000000000003'''
\set g_food  '00000000-0000-4000-a002-000000000101'
\set g_serv  '00000000-0000-4000-a002-000000000102'
\set g_value '00000000-0000-4000-a002-000000000103'
\set g_atmo  '00000000-0000-4000-a002-000000000104'

-- People: Alice, Bob and six more for community counts.
insert into auth.users (id) values (:alice), (:bob);
insert into auth.users (id) select ('b0000000-0000-4000-8000-00000000000' || n)::uuid from generate_series(1, 6) n;
select test.ok((select count(*) from public.profiles) = 8, 'a profile is created for every new account');

-- Standard systems are seeded and valid.
select test.ok((select count(*) from public.ranking_systems where owner_id is null) = 3, 'three standard systems seeded');
select test.ok((select bool_and(total = 10) from (
  select sum(max_points) total from public.ranking_criteria group by version_id) t), 'every seeded version totals 10');

-- ------------------------------------------------------------------ as Alice
set role authenticated;
select set_config('request.jwt.claim.sub', :alice, false) \g /dev/null

select id as rest from public.ensure_restaurant('google', 'place-1') \gset
insert into public.visits (user_id, restaurant_id, visited_on, visibility)
values (:alice, :'rest', current_date - 3, 'private') returning id as v_private \gset
insert into public.visits (user_id, restaurant_id, visited_on, visibility)
values (:alice, :'rest', current_date - 2, 'followers') returning id as v_followers \gset
insert into public.visits (user_id, restaurant_id, visited_on, visibility)
values (:alice, :'rest', current_date - 1, 'public') returning id as v_public \gset

-- Totals come from criterion scores.
select public.save_rating(:'v_public', :general_v1,
  jsonb_build_object(:'g_food', 4, :'g_serv', 2, :'g_value', 1, :'g_atmo', 1), true) as rev_public \gset
select test.ok((select total = 8 and state = 'active' from public.rating_revisions where id = :'rev_public'),
               'total is computed from criterion scores (4+2+1+1 = 8)');
select public.save_rating(:'v_private', :general_v1,
  jsonb_build_object(:'g_food', 5, :'g_serv', 2, :'g_value', 2, :'g_atmo', 1), true) \g /dev/null
select public.save_rating(:'v_followers', :general_v1,
  jsonb_build_object(:'g_food', 3, :'g_serv', 1, :'g_value', 1, :'g_atmo', 1), true) \g /dev/null

-- Clients cannot write ratings or totals directly.
select test.refused(format('insert into public.rating_revisions (visit_id, user_id, system_version_id, state, total) values (%L, %L, %L, ''active'', 10)',
                           :'v_public', :alice, :general_v1), 'direct insert of a rating with a client total');
select test.refused(format('update public.rating_revisions set total = 10 where id = %L', :'rev_public'), 'direct update of a total');
select test.refused(format('insert into public.criterion_scores values (%L, %L, 5)', :'rev_public', :'g_food'), 'direct insert of a score');

-- Range, membership and completeness.
select test.refused(format('select public.save_rating(%L, %L, %L::jsonb, true)', :'v_public', :general_v1,
  jsonb_build_object(:'g_food', 6, :'g_serv', 2, :'g_value', 1, :'g_atmo', 1)), 'score above the criterion maximum');
select test.refused(format('select public.save_rating(%L, %L, %L::jsonb, true)', :'v_public', :general_v1,
  jsonb_build_object(:'g_food', -1, :'g_serv', 2, :'g_value', 1, :'g_atmo', 1)), 'negative score');
select test.refused(format('select public.save_rating(%L, %L, %L::jsonb, true)', :'v_public', :general_v1,
  jsonb_build_object(:'g_food', 4, :'g_serv', 2, :'g_value', 1)), 'submitting with a criterion unanswered');
select test.refused(format('select public.save_rating(%L, %L, %L::jsonb, false)', :'v_public', :general_v1,
  jsonb_build_object('00000000-0000-4000-a002-000000000301', 1)), 'score for a criterion from another system');
select test.ok((select total = 8 from public.rating_revisions where visit_id = :'v_public' and state = 'active'),
               'rejected submissions leave the existing rating untouched');

-- Drafts are allowed to be incomplete and do not replace the submitted rating.
select public.save_rating(:'v_public', :general_v1, jsonb_build_object(:'g_food', 2), false) \g /dev/null
select test.ok((select count(*) = 1 from public.rating_revisions where visit_id = :'v_public' and state = 'draft' and total is null),
               'incomplete rating saved as a draft with no total');
select test.ok((select total = 8 from public.rating_revisions where visit_id = :'v_public' and state = 'active'),
               'the submitted rating still counts while a draft exists');
select public.discard_draft_rating(:'v_public') \g /dev/null

-- Editing scores supersedes rather than rewrites.
select public.save_rating(:'v_public', :general_v1,
  jsonb_build_object(:'g_food', 5, :'g_serv', 2, :'g_value', 2, :'g_atmo', 1), true) \g /dev/null
select test.ok((select count(*) filter (where state = 'active') = 1 and count(*) filter (where state = 'superseded') = 1
                from public.rating_revisions where visit_id = :'v_public'), 'editing keeps the previous revision as history');
select test.ok((select total = 8 from public.rating_revisions where id = :'rev_public'), 'the superseded revision keeps its original total');
select test.ok((select score = 4 from public.criterion_scores where revision_id = :'rev_public' and criterion_id = :'g_food'),
               'the superseded revision keeps its original scores');

-- Custom system: validation, versioning, immutability.
insert into public.ranking_systems (id, owner_id, name) values ('c0000000-0000-4000-8000-000000000001', :alice, 'Ramen');
\set ramen '''c0000000-0000-4000-8000-000000000001'''
\set bad_criteria '[{"name":"Broth","max_points":5,"levels":[{"points":0,"description":"a"},{"points":1,"description":"b"},{"points":2,"description":"c"},{"points":3,"description":"d"},{"points":4,"description":"e"},{"points":5,"description":"f"}]},{"name":"Noodles","max_points":3,"levels":[{"points":0,"description":"a"},{"points":1,"description":"b"},{"points":2,"description":"c"},{"points":3,"description":"d"}]}]'
\set missing_level '[{"name":"Broth","max_points":10,"levels":[{"points":0,"description":"a"},{"points":10,"description":"b"}]}]'
\set good_criteria '[{"name":"Broth","max_points":5,"levels":[{"points":0,"description":"a"},{"points":1,"description":"b"},{"points":2,"description":"c"},{"points":3,"description":"d"},{"points":4,"description":"e"},{"points":5,"description":"f"}]},{"name":"Noodles","max_points":3,"levels":[{"points":0,"description":"a"},{"points":1,"description":"b"},{"points":2,"description":"c"},{"points":3,"description":"d"}]},{"name":"Toppings","max_points":2,"levels":[{"points":0,"description":"a"},{"points":1,"description":"b"},{"points":2,"description":"c"}]}]'
\set changed_criteria '[{"name":"Broth","max_points":4,"levels":[{"points":0,"description":"a"},{"points":1,"description":"b"},{"points":2,"description":"c"},{"points":3,"description":"d"},{"points":4,"description":"e"}]},{"name":"Noodles","max_points":3,"levels":[{"points":0,"description":"a"},{"points":1,"description":"b"},{"points":2,"description":"c"},{"points":3,"description":"d"}]},{"name":"Toppings","max_points":3,"levels":[{"points":0,"description":"a"},{"points":1,"description":"b"},{"points":2,"description":"c"},{"points":3,"description":"d"}]}]'

select test.refused(format('select public.publish_system_version(%L, ''Ramen'', '''', %L::jsonb)', :ramen, :'bad_criteria'),
                    'publishing criteria that total 8, not 10');
select test.refused(format('select public.publish_system_version(%L, ''Ramen'', '''', %L::jsonb)', :ramen, :'missing_level'),
                    'publishing a criterion with undescribed scores');
select test.ok((select current_version_id is null from public.ranking_systems where id = :ramen), 'an invalid system stays a draft');

select public.publish_system_version(:ramen, 'Ramen', 'Bowls', :'good_criteria'::jsonb) as ramen_v1 \gset
select test.ok((select version_number = 1 from public.ranking_system_versions where id = :'ramen_v1'), 'first publish creates version 1');
select public.publish_system_version(:ramen, 'Noodle Soup', 'Bowls', :'good_criteria'::jsonb) as ramen_same \gset
select test.ok(:'ramen_same' = :'ramen_v1' and (select name = 'Noodle Soup' from public.ranking_systems where id = :ramen),
               'renaming alone does not create a version');

insert into public.visits (user_id, restaurant_id, visited_on, visibility)
values (:alice, :'rest', current_date, 'public') returning id as v_ramen \gset
select public.save_rating(:'v_ramen', :'ramen_v1', (
  select jsonb_object_agg(id::text, max_points) from public.ranking_criteria where version_id = :'ramen_v1'), true) as rev_ramen \gset
select test.definition(:'ramen_v1') as v1_before \gset

select public.publish_system_version(:ramen, 'Noodle Soup', 'Bowls', :'changed_criteria'::jsonb) as ramen_v2 \gset
select test.ok((select version_number = 2 from public.ranking_system_versions where id = :'ramen_v2')
               and (select current_version_id = :'ramen_v2' from public.ranking_systems where id = :ramen),
               'changing criteria creates version 2 and makes it current');
select test.ok(test.definition(:'ramen_v1') = :'v1_before'::jsonb, 'version 1 is unchanged by the edit');
select test.ok((select total = 10 and system_version_id = :'ramen_v1' and state = 'active' from public.rating_revisions where id = :'rev_ramen'),
               'the existing rating keeps version 1 and is not recalculated');

insert into public.visits (user_id, restaurant_id, visited_on) values (:alice, :'rest', current_date) returning id as v_new \gset
select test.refused(format('select public.save_rating(%L, %L, ''{}''::jsonb, false)', :'v_new', :'ramen_v1'),
                    'starting a new rating on an old version');
select public.save_rating(:'v_ramen', :'ramen_v2', (
  select jsonb_object_agg(id::text, 1) from public.ranking_criteria where version_id = :'ramen_v2'), true) \g /dev/null
select test.ok((select count(*) filter (where state = 'active' and system_version_id = :'ramen_v2' and total = 3) = 1
                   and count(*) filter (where state = 'superseded' and system_version_id = :'ramen_v1' and total = 10) = 1
                from public.rating_revisions where visit_id = :'v_ramen'),
               'explicit re-rating moves the visit to version 2 and keeps the version 1 rating as history');

select test.refused(format('delete from public.ranking_systems where id = %L', :ramen), 'deleting a system that has ratings');
update public.ranking_systems set is_archived = true where id = :ramen;
select test.refused(format('select public.save_rating(%L, %L, ''{}''::jsonb, false)', :'v_new', :'ramen_v2'),
                    'using an archived system for a new rating');
select test.ok((select count(*) = 3 from public.ranking_criteria where version_id = :'ramen_v1'), 'archived systems stay readable');
select test.refused(format('update public.ranking_systems set current_version_id = %L where id = %L', :general_v1, :ramen),
                    'pointing a system at an arbitrary version');
with u as (update public.ranking_systems set name = 'Hacked' where id = :general returning 1)
select test.ok((select count(*) = 0 from u), 'renaming a standard system affects nothing');
select test.refused(format('insert into public.ranking_systems (id, owner_id, name) values (gen_random_uuid(), null, %L)', 'Fake standard'),
                    'creating a standard (ownerless) system');

-- ------------------------------------------------------------------ as Bob
select set_config('request.jwt.claim.sub', :bob, false) \g /dev/null

select test.ok((select array_agg(id order by visited_on) = array[:'v_public'::uuid, :'v_ramen'::uuid] from public.visits where user_id = :alice),
               'a stranger sees only the public reviews');
select test.ok(not exists (select 1 from public.visits where id in (:'v_private', :'v_followers', :'v_new')),
               'private, followers-only and unrated visits are hidden from a stranger');
select test.ok(not exists (select 1 from public.rating_revisions r join public.visits v on v.id = r.visit_id where v.id = :'v_private'),
               'ratings of a private review are hidden');
select test.ok(not exists (select 1 from public.criterion_scores cs join public.rating_revisions r on r.id = cs.revision_id where r.visit_id = :'v_private'),
               'criterion scores of a private review are hidden');
select test.ok((select count(*) = 1 from public.rating_revisions where visit_id = :'v_public'),
               'others see only the current rating, never history or drafts');

insert into public.follows (follower_id, followee_id) values (:bob, :alice);
select test.ok(exists (select 1 from public.visits where id = :'v_followers'), 'a follower can read followers-only reviews');
select test.ok(not exists (select 1 from public.visits where id = :'v_private'), 'a follower still cannot read private reviews');

select test.refused(format('select public.save_rating(%L, %L, ''{}''::jsonb, false)', :'v_public', :general_v1), 'rating someone else''s visit');
with d as (delete from public.visits where id = :'v_public' returning 1)
select test.ok((select count(*) = 0 from d), 'deleting someone else''s visit affects nothing');
with u as (update public.visits set notes = 'x' where id = :'v_public' returning 1)
select test.ok((select count(*) = 0 from u), 'editing someone else''s visit affects nothing');
select test.refused(format('insert into public.visits (user_id, restaurant_id, visited_on) values (%L, %L, current_date)', :alice, :'rest'),
                    'creating a visit in someone else''s name');
select test.refused(format('select public.publish_system_version(%L, ''Mine now'', '''', %L::jsonb)', :ramen, :'good_criteria'),
                    'publishing to a system you do not own');
with u as (update public.ranking_systems set name = 'x' where id = :ramen returning 1)
select test.ok((select count(*) = 0 from u), 'renaming someone else''s system affects nothing');
select test.ok(exists (select 1 from public.ranking_criteria where version_id = :'ramen_v2'),
               'a custom system''s definition is readable through a public review that uses it');
select test.refused(format('insert into public.follows (follower_id, followee_id) values (%L, %L)', :alice, :bob), 'creating a follow on someone else''s behalf');

-- Bob rates with the custom system? Not allowed: it belongs to Alice.
insert into public.visits (user_id, restaurant_id, visited_on, visibility) values (:bob, :'rest', current_date, 'public') returning id as v_bob \gset
select test.refused(format('select public.save_rating(%L, %L, ''{}''::jsonb, false)', :'v_bob', :'ramen_v2'), 'rating with another person''s custom system');
select public.save_rating(:'v_bob', :general_v1, jsonb_build_object(:'g_food', 2, :'g_serv', 1, :'g_value', 1, :'g_atmo', 0), true) \g /dev/null
-- A second, older visit by Bob must not count twice.
insert into public.visits (user_id, restaurant_id, visited_on, visibility) values (:bob, :'rest', current_date - 30, 'public') returning id as v_bob_old \gset
select public.save_rating(:'v_bob_old', :general_v1, jsonb_build_object(:'g_food', 5, :'g_serv', 2, :'g_value', 2, :'g_atmo', 1), true) \g /dev/null
-- And a Fast Casual rating must not be mixed into General.
insert into public.visits (user_id, restaurant_id, visited_on, visibility) values (:bob, :'rest', current_date - 5, 'public') returning id as v_bob_fc \gset
select public.save_rating(:'v_bob_fc', :fast_v1, (select jsonb_object_agg(id::text, 0) from public.ranking_criteria where version_id = :fast_v1), true) \g /dev/null

-- Community: Alice's latest public General is 10 (edited), Bob's latest is 4. Private and followers-only are excluded.
select test.ok((select user_count = 2 and average = 7.0 from public.community_scores('google', 'place-1') where system_id = :general),
               'community average counts each person once, by latest public visit: (10 + 4) / 2');
select test.ok((select count(*) = 2 from public.community_scores('google', 'place-1')),
               'one bucket per standard system version; the custom system has none');
select test.ok((select user_count = 1 and average = 0.0 from public.community_scores('google', 'place-1') where version_id = :fast_v1),
               'Fast Casual is averaged on its own');
select test.ok((select (criteria -> 0 ->> 'average')::numeric = 3.5 from public.community_scores('google', 'place-1') where system_id = :general),
               'criterion averages are per criterion: Food (5 + 2) / 2');

-- Removing the follower closes followers-only reviews again.
select set_config('request.jwt.claim.sub', :alice, false) \g /dev/null
delete from public.follows where follower_id = :bob and followee_id = :alice;
select set_config('request.jwt.claim.sub', :bob, false) \g /dev/null
select test.ok(not exists (select 1 from public.visits where id = :'v_followers'), 'a removed follower loses followers-only access');

-- ------------------------------------------------------------------ as the database owner
reset role;
select test.refused(format('update public.rating_revisions set total = 1 where id = %L', :'rev_public'),
                    'even a privileged writer cannot rewrite a superseded rating');
select test.refused(format('update public.ranking_criteria set max_points = 9 where version_id = %L', :general_v1), 'changing a published criterion');
select test.refused(format('update public.criterion_score_levels set description = ''x'' where criterion_id = %L', :'g_food'), 'changing a published score description');
select test.refused(format('insert into public.ranking_criteria (version_id, position, name, max_points) values (%L, 9, ''Extra'', 1)', :general_v1),
                    'adding a criterion to a published version');
-- The validity check is deferred to commit; forcing it here shows it firing.
select test.refused($$insert into public.ranking_system_versions (system_id, version_number) values ('00000000-0000-4000-a000-000000000001', 2);
                      set constraints all immediate$$,
                    'a version whose criteria do not total 10 fails the commit-time check');

-- Coordinates are purged after 30 days; the place ID stays.
update public.restaurants set lat = 1, lng = 2, location_cached_at = now() - interval '31 days' where id = :'rest';
select app_private.purge_stale_restaurant_locations() \g /dev/null
select test.ok((select lat is null and lng is null and provider_place_id = 'place-1' from public.restaurants where id = :'rest'),
               'stale coordinates are purged; the place ID is kept');

-- Account deletion removes everything the person owned and nothing else.
delete from auth.users where id = :alice;
select test.ok(not exists (select 1 from public.visits where user_id = :alice)
               and not exists (select 1 from public.ranking_systems where id = :ramen)
               and not exists (select 1 from public.profiles where id = :alice),
               'deleting an account removes its visits, ratings and custom systems');
select test.ok((select count(*) = 3 from public.visits where user_id = :bob)
               and (select count(*) = 3 from public.ranking_systems where owner_id is null),
               'other people''s data and the standard systems are untouched');

select 'ALL BACKEND RULE TESTS PASSED';
