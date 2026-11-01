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
select test.refused(format('insert into public.visits (user_id, restaurant_id, visited_on) values (%L, %L, current_date)', :alice, :'rest'),
                    'posting a review before accepting the terms');
select test.refused(format('update public.profiles set terms_accepted_at = now() where id = %L', :alice),
                    'setting the terms date without going through accept_terms()');
select public.accept_terms() \g /dev/null
select test.ok((select terms_accepted_at is not null from public.profiles where id = :alice), 'accepting the terms records when');
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
select public.accept_terms() \g /dev/null

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

-- ------------------------------------------------------------------ text filter
select test.refused(format('insert into public.visits (user_id, restaurant_id, visited_on, notes) values (%L, %L, current_date, %L)', :bob, :'rest', 'K1LL   y0urs3lf!!'),
                    'a note with a blocked phrase, disguised with swapped letters');
select test.refused(format('update public.visits set notes = %L where id = %L', 'killl yourselfff', :'v_bob'), 'a blocked phrase with stretched letters');
select test.refused(format('update public.visits set notes = %L where id = %L', 'kiiill yourself', :'v_bob'), 'a blocked phrase stretched on a single letter');
select test.refused(format('insert into public.visits (user_id, restaurant_id, visited_on, dishes) values (%L, %L, current_date, %L)', :bob, :'rest', '{Soup,"go die"}'),
                    'a dish with a blocked phrase');
select test.refused(format('update public.visits set notes = %L where id = %L', 'kill yourself', :'v_bob'), 'editing a note to add a blocked phrase');
select test.refused(format('update public.profiles set display_name = %L where id = %L', 'kill yourself', :bob), 'a display name with a blocked phrase');
select test.refused(format('update public.profiles set username = %L where id = %L', 'kill_yourself', :bob), 'a username with a blocked phrase');
select test.refused(format('insert into public.ranking_systems (owner_id, name) values (%L, %L)', :bob, 'kill yourself'), 'a system name with a blocked phrase');
\set rude_criteria '[{"name":"kill yourself","max_points":10,"levels":[{"points":0,"description":"a"},{"points":1,"description":"a"},{"points":2,"description":"a"},{"points":3,"description":"a"},{"points":4,"description":"a"},{"points":5,"description":"a"},{"points":6,"description":"a"},{"points":7,"description":"a"},{"points":8,"description":"a"},{"points":9,"description":"a"},{"points":10,"description":"a"}]}]'
insert into public.ranking_systems (id, owner_id, name) values ('c0000000-0000-4000-8000-000000000002', :bob, 'Bob scale');
select test.refused(format('select public.publish_system_version(%L, ''Bob scale'', '''', %L::jsonb)', 'c0000000-0000-4000-8000-000000000002', :'rude_criteria'),
                    'a criterion name with a blocked phrase');
delete from public.ranking_systems where id = 'c0000000-0000-4000-8000-000000000002';
update public.visits set notes = 'Skillful cooking, and the pasta was shit-hot. Pros and cons, like Niger stew' where id = :'v_bob';
select test.ok((select notes like 'Skillful%' from public.visits where id = :'v_bob'), 'ordinary words and mild swearing are allowed');

-- ------------------------------------------------------------------ reporting
select set_config('request.jwt.claim.sub', :alice, false) \g /dev/null
select test.refused(format('select public.report_content(''visit'', %L, ''spam'')', :'v_public'), 'reporting your own review');
select test.refused(format('select public.report_content(''user'', %L, ''spam'')', :alice), 'reporting yourself');
select set_config('request.jwt.claim.sub', :bob, false) \g /dev/null
select test.refused(format('select public.report_content(''visit'', %L, ''spam'')', :'v_private'), 'reporting a review you cannot read');
select test.refused($$insert into public.reports (target_type, target_id, reported_user_id, reason, snapshot)
                      values ('user', gen_random_uuid(), gen_random_uuid(), 'spam', '{}')$$, 'writing a report directly');
select set_config('request.jwt.claim.sub', :alice, false) \g /dev/null
update public.visits set notes = 'Reported words', dishes = '{Soup}' where id = :'v_public';
insert into public.visit_photos (visit_id, user_id, storage_path)
values (:'v_public', :alice, :alice || '/' || :'v_public' || '/one.jpg') returning id as photo_one \gset
select set_config('request.jwt.claim.sub', :bob, false) \g /dev/null
select public.report_content('visit', :'v_public', 'harassment', 'Mean about me') \g /dev/null
select public.report_content('visit', :'v_public', 'harassment', 'Twice') \g /dev/null
select public.report_content('photo', :'photo_one', 'sexual') \g /dev/null
select public.report_content('user', :alice, 'hate') \g /dev/null
select test.ok(not exists (select 1 from public.reports), 'nobody but a moderator can read reports, including the reporter');
select test.refused(format('select public.moderate_report(gen_random_uuid(), %L)', 'dismiss'), 'moderating without being a moderator');
select test.refused(format('select public.finish_report(gen_random_uuid(), %L)', 'dismiss'), 'closing a report without being a moderator');
select test.ok(not public.is_moderator(), 'ordinary members are not moderators');

reset role;
select test.ok((select count(*) = 3 from public.reports), 'each report arrives once; a repeat of an open report adds nothing');
select test.ok((select snapshot ->> 'notes' = 'Reported words' and snapshot -> 'dishes' ? 'Soup' and snapshot ->> 'username' like 'user_%'
                       and snapshot ->> 'system_name' = 'General' and jsonb_array_length(snapshot -> 'photo_paths') = 1
                from public.reports where target_type = 'visit'), 'a report keeps a snapshot of what was reported');
-- Carol moderates. She has no follow or block links to anyone.
\set carol '''b0000000-0000-4000-8000-000000000001'''
\set dave  '''b0000000-0000-4000-8000-000000000002'''
insert into app_private.moderators (user_id) values (:carol);
insert into storage.objects (bucket_id, name) values ('visit-photos', :alice || '/' || :'v_public' || '/one.jpg');
select id as report_visit from public.reports where target_type = 'visit' \gset
select id as report_photo from public.reports where target_type = 'photo' \gset
select id as report_user from public.reports where target_type = 'user' \gset
set role authenticated;

select set_config('request.jwt.claim.sub', :carol, false) \g /dev/null
select test.ok(public.is_moderator(), 'a moderator is recognised');
select test.ok((select count(*) = 3 from public.reports where status = 'open'), 'a moderator can read the queue');
select test.ok((select count(*) = 1 from storage.objects where name like '%/one.jpg'), 'a moderator can open a reported photo');
select test.refused(format('select public.moderate_report(%L, %L)', :'report_visit', 'nonsense'), 'an unknown moderation action');
select public.finish_report(:'report_photo', 'dismiss') \g /dev/null
select test.ok((select status = 'dismissed' and resolved_by = :carol from public.reports where id = :'report_photo'), 'dismissing closes the report and records who did it');
select public.moderate_report(:'report_visit', 'remove_content') as removal \gset
select test.ok((:'removal')::jsonb -> 'storage_paths' ? (:alice || '/' || :'v_public' || '/one.jpg'), 'removing a review says which photo files to delete');
select test.ok(not exists (select 1 from public.visits where id = :'v_public'), 'removing a review deletes it, whatever its owner');
select test.ok((select status = 'open' from public.reports where id = :'report_visit'), 'a report stays open until every removal step has finished');
select public.finish_report(:'report_visit', 'remove_content') \g /dev/null
select test.ok((select status = 'actioned' and resolution = 'remove_content' from public.reports where id = :'report_visit'), 'finishing closes the report');
select test.ok((select snapshot ->> 'notes' = 'Reported words' from public.reports where id = :'report_visit'), 'the snapshot survives the removal');
select test.ok(not exists (select 1 from storage.objects where name like '%/one.jpg'), 'a moderator can no longer open a photo once its report is closed');
select test.refused(format('select public.moderate_report(%L, %L)', :'report_visit', 'dismiss'), 'moderating a closed report');
select public.moderate_report(:'report_user', 'remove_content') \g /dev/null
select test.ok((select username like 'user_%' and display_name = 'New member' from public.profiles where id = :alice), 'removing a person''s content resets their names');
select public.finish_report(:'report_user', 'remove_content') \g /dev/null
-- The rest of the file expects Alice's public review to exist.
select set_config('request.jwt.claim.sub', :alice, false) \g /dev/null
insert into public.visits (user_id, restaurant_id, visited_on, visibility)
values (:alice, :'rest', current_date - 1, 'public') returning id as v_public \gset
select public.save_rating(:'v_public', :general_v1,
  jsonb_build_object(:'g_food', 5, :'g_serv', 2, :'g_value', 2, :'g_atmo', 1), true) as rev_public \gset
update public.profiles set username = 'alice', display_name = 'Alice' where id = :alice;

-- ------------------------------------------------------------------ blocking
insert into public.follows (follower_id, followee_id) values (:alice, :bob);
select set_config('request.jwt.claim.sub', :bob, false) \g /dev/null
insert into public.follows (follower_id, followee_id) values (:bob, :alice);
select set_config('request.jwt.claim.sub', :alice, false) \g /dev/null
insert into public.blocks (blocker_id, blocked_id) values (:alice, :bob);
select test.ok(not exists (select 1 from public.follows where :alice in (follower_id, followee_id)), 'blocking removes the follow in both directions');
select test.ok((select array_agg(id) = array[:bob::uuid] from public.blocked_users()), 'the blocker can list who they blocked');
select test.ok(not exists (select 1 from public.profiles where id = :bob), 'the blocker no longer finds the blocked person');
select test.ok(not exists (select 1 from public.visits where user_id = :bob), 'the blocker no longer sees the blocked person''s reviews');
select test.refused(format('insert into public.blocks (blocker_id, blocked_id) values (%L, %L)', :bob, :carol), 'blocking on someone else''s behalf');

select set_config('request.jwt.claim.sub', :bob, false) \g /dev/null
select test.ok(not exists (select 1 from public.blocks), 'the blocked person cannot see that they were blocked');
select test.ok(not exists (select 1 from public.profiles where id = :alice), 'the blocked person cannot find the blocker');
select test.ok(not exists (select 1 from public.profiles where username = 'alice' or display_name = 'Alice'), 'the blocked person cannot search for the blocker');
select test.ok(not exists (select 1 from public.visits where user_id = :alice), 'the blocked person cannot read the blocker''s public reviews');
select test.ok(not exists (select 1 from public.rating_revisions where visit_id = :'v_public'), 'the blocked person cannot read the blocker''s ratings');
select test.ok(not exists (select 1 from public.criterion_scores where revision_id = :'rev_public'), 'the blocked person cannot read the blocker''s scores');
select test.ok(not exists (select 1 from public.ranking_systems where owner_id = :alice), 'the blocked person cannot read custom systems through the blocker''s reviews');
select test.refused(format('insert into public.follows (follower_id, followee_id) values (%L, %L)', :bob, :alice), 'following someone who blocked you');
select test.refused(format('select public.report_content(''visit'', %L, ''spam'')', :'v_public'), 'reporting a review a block hides');
select test.ok((select user_count = 2 from public.community_scores('google', 'place-1') where system_id = :general),
               'community scores are anonymous averages, so a block does not change them');

select set_config('request.jwt.claim.sub', :alice, false) \g /dev/null
select test.refused(format('insert into public.follows (follower_id, followee_id) values (%L, %L)', :alice, :bob), 'following someone you blocked');
select public.report_content('user', :bob, 'harassment') \g /dev/null
delete from public.blocks where blocker_id = :alice and blocked_id = :bob;
select test.ok(exists (select 1 from public.profiles where id = :bob), 'unblocking restores the person');
select test.ok(exists (select 1 from public.visits where user_id = :bob), 'unblocking restores their reviews');
select set_config('request.jwt.claim.sub', :bob, false) \g /dev/null
select test.ok(exists (select 1 from public.visits where id = :'v_public'), 'unblocking restores the blocker''s reviews to the other person');
select test.ok(not exists (select 1 from public.follows where :bob in (follower_id, followee_id)), 'unblocking does not restore the old follows');

-- ------------------------------------------------------------------ bans
select set_config('request.jwt.claim.sub', :dave, false) \g /dev/null
select public.accept_terms() \g /dev/null
select public.report_content('user', :bob, 'spam') \g /dev/null
insert into public.follows (follower_id, followee_id) values (:dave, :bob);
reset role;
select id as report_bob from public.reports where reported_user_id = :bob and status = 'open' and reporter_id = :dave \gset
set role authenticated;
select set_config('request.jwt.claim.sub', :carol, false) \g /dev/null
select public.moderate_report(:'report_bob', 'ban') as ban \gset
select test.ok((:'ban')::jsonb ->> 'ban_user_id' = :bob, 'a ban tells the Edge Function whose sign-in to stop');
select test.refused(format('select public.moderate_report(%L, %L)', :'report_user', 'ban'), 'acting on a report already closed');
select public.finish_report(:'report_bob', 'ban') \g /dev/null
select test.ok(not exists (select 1 from public.reports where reported_user_id = :bob and status = 'open'), 'a ban closes every open report against that person');
select set_config('request.jwt.claim.sub', :dave, false) \g /dev/null
select test.ok(not exists (select 1 from public.profiles where id = :bob), 'a banned person can no longer be found');
select test.ok(not exists (select 1 from public.visits where user_id = :bob), 'a banned person''s reviews disappear');
select test.ok(not exists (select 1 from public.follows where :bob in (follower_id, followee_id)), 'a ban removes their follows');
select test.ok((select user_count = 1 and average = 10 from public.community_scores('google', 'place-1') where system_id = :general),
               'a banned person no longer counts toward community scores');
select test.refused(format('insert into public.follows (follower_id, followee_id) values (%L, %L)', :dave, :bob), 'following a banned person');

reset role;
select test.ok(exists (select 1 from app_private.banned_users where user_id = :bob), 'the ban is recorded');
delete from app_private.banned_users where user_id = :bob;

-- A name from the sign-in provider is dropped rather than refusing the account.
insert into auth.users (id, raw_user_meta_data) values ('b0000000-0000-4000-8000-000000000009', '{"full_name": "Kill Yourself"}');
select test.ok((select display_name = 'New member' from public.profiles where id = 'b0000000-0000-4000-8000-000000000009'),
               'a blocked name from the sign-in provider does not stop the account being created');

-- ------------------------------------------------------------------ as the database owner
select test.refused(format('update public.rating_revisions set total = 1 where id = %L', (
                      select id from public.rating_revisions where state = 'superseded' limit 1)),
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
