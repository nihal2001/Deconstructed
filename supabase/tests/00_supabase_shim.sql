-- Minimal stand-ins for the parts of Supabase the migrations rely on, so they can be
-- exercised on a plain Postgres. NOT part of the deployed schema: never run this on Supabase.

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  raw_user_meta_data jsonb not null default '{}'
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
grant usage on schema auth to anon, authenticated;

create schema storage;
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text not null,
  owner uuid
);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1 : array_length(string_to_array(name, '/'), 1) - 1];
$$;
grant usage on schema storage to authenticated;
grant select, insert, delete on storage.objects to authenticated;

grant usage on schema public to anon, authenticated;

-- Test helpers
create schema test;
grant usage on schema test to public;

create function test.ok(p_condition boolean, p_label text) returns text language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'FAILED: %', p_label;
  end if;
  return 'ok - ' || p_label;
end;
$$;

-- Runs a statement as the current role and reports whether it was refused.
create function test.refused(p_sql text, p_label text) returns text language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    return 'ok - refused: ' || p_label || '  [' || sqlerrm || ']';
  end;
  raise exception 'FAILED: expected to be refused: %', p_label;
end;
$$;

-- Everything the caller can read about a version, for before/after comparisons.
create function test.definition(p_version_id uuid) returns jsonb language plpgsql as $$
begin
  return (
    select jsonb_agg(to_jsonb(c) || jsonb_build_object('levels', (
             select jsonb_agg(to_jsonb(l) order by l.points)
             from public.criterion_score_levels l where l.criterion_id = c.id))
           order by c.position)
    from public.ranking_criteria c where c.version_id = p_version_id);
end;
$$;
