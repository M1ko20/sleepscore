-- Push (#10): registrace tokenů, úklid fronty, tick (volá send-push jen když je co poslat),
-- dávka po uživatelích, škrcení reakcí, noční klid, neplatné tokeny, cache JWT.
-- Spouští run.sh.
\set ON_ERROR_STOP 1

create function public.t_ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAIL: %', msg; end if;
  raise notice 'ok  %', msg;
end;
$$;
create function public.t_err(p_sql text, p_expect text, msg text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAIL: % (nespadlo)', msg;
exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if position(p_expect in sqlerrm) = 0 then
    raise exception 'FAIL: % (čekal jsem "%", přišlo "%")', msg, p_expect, sqlerrm;
  end if;
  raise notice 'ok  %', msg;
end;
$$;
grant execute on function public.t_ok(boolean, text), public.t_err(text, text, text) to authenticated;

-- A Praha s tokenem, B bez tokenu, C má vypnuté reakce, D New York (noční klid), E zabanovaný.
insert into auth.users (id) values
  ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-00000000000b'),
  ('00000000-0000-0000-0000-00000000000c'), ('00000000-0000-0000-0000-00000000000d'),
  ('00000000-0000-0000-0000-00000000000e');
insert into public.profiles (id, username, display_name, timezone, banned_at) values
  ('00000000-0000-0000-0000-00000000000a', 'adam', 'Adam', 'Europe/Prague', null),
  ('00000000-0000-0000-0000-00000000000b', 'bara', 'Bára', 'Europe/Prague', null),
  ('00000000-0000-0000-0000-00000000000c', 'cyril', 'Cyril', 'Europe/Prague', null),
  ('00000000-0000-0000-0000-00000000000d', 'dana', 'Dana', 'America/New_York', null),
  ('00000000-0000-0000-0000-00000000000e', 'eda', 'Eda', 'Europe/Prague', now());
insert into public.notification_prefs (user_id, prefs) values
  ('00000000-0000-0000-0000-00000000000c', private.notification_prefs_default() || '{"reactions": false}');

-- ---------------------------------------------------------------------
-- Registrace tokenů
-- ---------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select public.register_push_token(repeat('a', 64), 'sandbox');
select t_ok((select env from public.push_tokens where token = repeat('a', 64)) = 'sandbox', 'A: token uložený se sandboxem');
select public.register_push_token(repeat('a', 64), 'sandbox');
select t_ok((select count(*) from public.push_tokens) = 1, 'opakovaná registrace = pořád 1 řádek');
select t_err($$select public.register_push_token('nejsem-token')$$, 'invalid token', 'nesmyslný token');
select t_err($$select public.register_push_token(repeat('f', 64), 'dev')$$, 'invalid env', 'neznámé prostředí');
select t_err($$insert into public.push_tokens (token, user_id) values (repeat('f', 64), auth.uid())$$,
  'permission denied', 'přímý insert už nejde');
select t_err($$select public.claim_push_batch()$$, 'permission denied', 'klient nevolá claim_push_batch');
select t_err($$select public.finish_push_batch()$$, 'permission denied', 'klient nevolá finish_push_batch');
select t_err($$select private.push_tick()$$, 'permission denied', 'klient nevolá push_tick');

-- telefon přejde na jiný účet: token se přestěhuje (A ho nevidí, nesmaže)
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
select public.register_push_token(repeat('a', 64), 'production');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select t_ok((select count(*) from public.push_tokens) = 0, 'token po přestěhování A nevidí');
select public.unregister_push_token(repeat('a', 64));
reset role;
select t_ok((select user_id from public.push_tokens where token = repeat('a', 64)) = '00000000-0000-0000-0000-00000000000c',
  'A cizí token odregistrací nesmaže; patří C, production');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select public.register_push_token(repeat('1', 64), 'production');
select public.register_push_token(repeat('2', 64), 'sandbox');   -- druhý telefon
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', false);
select public.register_push_token(repeat('d', 64));
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000e', false);
select t_err($$select public.register_push_token(repeat('e', 64))$$, 'not a member', 'zabanovaný token neuloží');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select public.register_push_token(repeat('b', 64));
select public.unregister_push_token(repeat('b', 64));
select t_ok((select count(*) from public.push_tokens) = 0, 'B: odhlášení token smaže');
reset role;

-- ---------------------------------------------------------------------
-- Tick a dávka. Teď = 12:00 UTC (13:00 Praha, 7:00 New York).
-- ---------------------------------------------------------------------
-- A: 3 čerstvé (žádost, odznak, reakce), 1 stará (2 dny)
insert into public.notifications (user_id, kind, actor_id, payload, created_at) values
  ('00000000-0000-0000-0000-00000000000a', 'friend_request', '00000000-0000-0000-0000-00000000000b', '{}', '2026-11-09 11:50+00'),
  ('00000000-0000-0000-0000-00000000000a', 'achievement', null, '{"code": "nope"}', '2026-11-09 11:55+00'),
  ('00000000-0000-0000-0000-00000000000a', 'weekly_recap', null, '{"week_start": "2026-11-02", "nights": 2, "avg_score": 75}', '2026-11-07 11:00+00');
-- B bez tokenu, C reakce vypnuté + žádost, D v nočním klidu
insert into public.notifications (user_id, kind, actor_id, payload, created_at) values
  ('00000000-0000-0000-0000-00000000000b', 'friend_request', '00000000-0000-0000-0000-00000000000a', '{}', '2026-11-09 11:59+00'),
  ('00000000-0000-0000-0000-00000000000c', 'reaction', '00000000-0000-0000-0000-00000000000a', '{}', '2026-11-09 11:59+00'),
  ('00000000-0000-0000-0000-00000000000c', 'friend_accepted', '00000000-0000-0000-0000-00000000000a', '{}', '2026-11-09 11:58+00'),
  ('00000000-0000-0000-0000-00000000000d', 'friend_request', '00000000-0000-0000-0000-00000000000a', '{}', '2026-11-09 11:59+00');

-- bez URL: úklid ano, call ne
select t_ok(private.push_tick('2026-11-09 12:00+00') = 3, 'připravené: 2× A, 1× C');
select t_ok((select count(*) from net.requests) = 0, 'bez push_function_url žádný call');
select t_ok((select pushed_at from public.notifications where kind = 'weekly_recap') is not null, 'starší než den vypadne z fronty');
select t_ok((select pushed_at from public.notifications where user_id = '00000000-0000-0000-0000-00000000000b') is not null,
  'bez tokenu vypadne z fronty');
select t_ok((select pushed_at from public.notifications where kind = 'reaction') is not null, 'vypnutá kategorie vypadne');
select t_ok((select pushed_at from public.notifications where user_id = '00000000-0000-0000-0000-00000000000d') is null,
  'noční klid zůstává ve frontě');

insert into private.app_config values ('push_function_url', 'https://x.test/functions/v1/send-push'), ('push_secret', 's3cret');
select private.push_tick('2026-11-09 12:00+00');
select t_ok((select count(*) from net.requests) = 1, 'je co poslat → 1 call');
select t_ok((select headers ->> 'x-push-secret' from net.requests) = 's3cret', 'call nese tajemství');

-- claim jako service role
set role service_role;
create temp table b as select public.claim_push_batch(500, '2026-11-09 12:00+00') as r;
reset role;
select t_ok(jsonb_array_length((select r -> 'pushes' from b)) = 2, 'dávka: A a C, 1 push na uživatele');
select t_ok((select r -> 'jwt' from b) = 'null'::jsonb, 'JWT zatím v cache není');
create temp table pa as select p from b, jsonb_array_elements(b.r -> 'pushes') p
  where p ->> 'user_id' = '00000000-0000-0000-0000-00000000000a';
select t_ok((select p ->> 'body' from pa) = E'Nový odznak: nope.\n+1 další',
  'A: nejnovější text + „+1 další“');
select t_ok((select p -> 'link' ->> 't' from pa) = 'notifications', 'víc naráz → zvoneček');
select t_ok(jsonb_array_length((select p -> 'tokens' from pa)) = 2, 'A: oba telefony');
select t_ok((select (p ->> 'badge')::int from pa) = 3, 'badge = nepřečtené (i ty staré)');
create temp table pc as select p from b, jsonb_array_elements(b.r -> 'pushes') p
  where p ->> 'user_id' = '00000000-0000-0000-0000-00000000000c';
select t_ok((select p ->> 'body' from pc) = 'Adam přijímá žádost o přátelství.', 'C: jeden text');
select t_ok((select p -> 'link' ->> 't' from pc) = 'profile'
        and (select p -> 'link' -> 'profile' ->> 'username' from pc) = 'adam', 'C: proklik na profil s daty');

select t_ok(private.push_tick('2026-11-09 12:01+00') = 0, 'po claimu nic ve frontě');
select t_ok((select count(*) from net.requests) = 1, 'prázdná fronta → žádný další call');

-- D v 8:00 New York (13:00 UTC) odejde
select t_ok(private.push_tick('2026-11-09 13:00+00') = 1, 'D po nočním klidu připravená');

-- ---------------------------------------------------------------------
-- Reakce: max 1 push za hodinu na kartu
-- ---------------------------------------------------------------------
insert into public.notifications (user_id, kind, actor_id, payload, created_at) values
  ('00000000-0000-0000-0000-00000000000a', 'reaction', '00000000-0000-0000-0000-00000000000b', '{}', '2026-11-09 13:00+00');
set role service_role;
select public.claim_push_batch(500, '2026-11-09 13:00+00');
reset role;
-- další reakce za 10 min (slučování posune created_at)
update public.notifications set count = 2, created_at = '2026-11-09 13:10+00' where kind = 'reaction' and user_id = '00000000-0000-0000-0000-00000000000a';
select t_ok(not private.push_ready(n, '2026-11-09 13:10+00'), 'reakce za 10 min nepushne')
  from public.notifications n where kind = 'reaction' and user_id = '00000000-0000-0000-0000-00000000000a';
select t_ok(private.push_ready(n, '2026-11-09 14:01+00'), 'po hodině ano')
  from public.notifications n where kind = 'reaction' and user_id = '00000000-0000-0000-0000-00000000000a';

-- ---------------------------------------------------------------------
-- finish: neplatné tokeny, JWT cache
-- ---------------------------------------------------------------------
set role service_role;
select public.finish_push_batch(array[repeat('2', 64)], 'jwt.x.y', 1762700000);
reset role;
select t_ok(not exists (select 1 from public.push_tokens where token = repeat('2', 64)), 'neplatný token smazaný');
select t_ok(exists (select 1 from public.push_tokens where token = repeat('1', 64)), 'platný zůstal');
set role service_role;
select t_ok((public.claim_push_batch() -> 'jwt' ->> 'iat')::bigint = 1762700000, 'JWT z cache se vrací');
select public.finish_push_batch(p_clear_jwt => true);
select t_ok(public.claim_push_batch() -> 'jwt' = 'null'::jsonb, 'odmítnutý JWT smazaný');
reset role;

select t_ok((select count(*) from cron.job where jobname = 'push-tick' and schedule = '* * * * *') = 1, 'cron každou minutu');
