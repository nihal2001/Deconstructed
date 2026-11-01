-- Decisions from the pre-launch moderation review. See docs/moderation.md.

-- ---------------------------------------------------------------------------------------
-- Blocked terms
-- ---------------------------------------------------------------------------------------

-- These block ordinary text: "spic and span", the surnames Dyke and Coon, and "to go. Die-hard
-- fans", which reads "to go die hard fans" once punctuation is removed. Reports cover them.
delete from app_private.blocked_terms
where term in ('spic', 'dyke', 'dykes', 'coon', 'coons', 'go die');

insert into app_private.blocked_terms (term) values
  ('beaner'), ('beaners'), ('chinky'), ('jigaboo'), ('jigaboos'),
  ('porch monkey'), ('porch monkeys'), ('sandnigger'), ('sandniggers'),
  ('shemale'), ('shemales'), ('slut'), ('sluts'),
  ('child pornography'),
  ('i will hurt you'), ('im going to kill you'), ('i am going to kill you'), ('gonna kill you'),
  ('sieg heil')
on conflict do nothing;

-- ---------------------------------------------------------------------------------------
-- Report retention
-- ---------------------------------------------------------------------------------------

-- Closed reports hold copies of deleted content and the reported person's ID, so they're kept
-- for 12 months and then removed. The privacy policy states this period. Open reports stay.
create function app_private.purge_closed_reports() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  delete from public.reports
  where status <> 'open' and resolved_at < now() - interval '12 months';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('purge-closed-reports', '37 3 * * *', 'select app_private.purge_closed_reports()');
  else
    raise notice 'pg_cron is not enabled: enable it and schedule app_private.purge_closed_reports() daily (see README).';
  end if;
end;
$$;
