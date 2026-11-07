-- Stub Supabase pro lokální testy SQL (Postgres 16 bez Dockeru): auth.uid(), storage, pg_cron.
-- Role anon/authenticated/service_role zakládá run.sh. Default privileges jako na Supabase.
create schema auth; create schema storage;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth, storage, public to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$ select (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1] $$;
grant execute on function storage.foldername(text) to authenticated;
grant select, insert, update, delete on storage.objects to authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
create schema cron;
create table cron.job (jobid serial primary key, jobname text unique, schedule text, command text);
create table cron.job_run_details (end_time timestamptz);
create function cron.schedule(n text, s text, c text) returns int language sql as $$
  insert into cron.job (jobname, schedule, command) values (n, s, c)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command returning jobid $$;
create function cron.unschedule(n text) returns boolean language sql as $$ delete from cron.job where jobname = n returning true $$;
