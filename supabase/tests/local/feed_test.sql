-- Feed: feed_night_posts / feed_result_posts vrací totéž co dřívější dotaz přes RLS,
-- a nečtou celou tabulku karet. Spouští run.sh.
\set ON_ERROR_STOP 1

create function public.t_ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAIL: %', msg; end if;
  raise notice 'ok  %', msg;
end;
$$;
grant execute on function public.t_ok(boolean, text) to authenticated;

-- u('0a') = 00000000-0000-0000-0000-00000000000a
create function public.u(x text) returns uuid language sql immutable as $$
  select ('00000000-0000-0000-0000-0000000000' || x)::uuid;
$$;
create function public.t_as(p_user text) returns text language sql as $$
  select set_config('request.jwt.claim.sub', public.u(p_user)::text, false);
$$;
grant execute on function public.u(text), public.t_as(text) to authenticated;

-- Dřívější dotaz appky (RLS) vs. nové RPC – stejné id ve stejném pořadí.
create function public.t_same(p_user text) returns void language plpgsql as $$
declare old_n uuid[]; new_n uuid[]; old_r uuid[]; new_r uuid[];
begin
  perform public.t_as(p_user);
  old_n := array(select id from public.posts where kind = 'night' order by created_at desc, id desc limit 30);
  new_n := array(select id from public.feed_night_posts(30));
  old_r := array(select id from public.posts where kind = 'challenge_result' order by created_at desc, id desc limit 20);
  new_r := array(select id from public.feed_result_posts(20));
  perform public.t_ok(old_n = new_n, format('%s: noci stejné jako přes RLS (%s)', p_user, cardinality(new_n)));
  perform public.t_ok(old_r = new_r, format('%s: výsledky stejné jako přes RLS (%s)', p_user, cardinality(new_r)));
end;
$$;
grant execute on function public.t_same(text) to authenticated;

-- A–B, A–E, B–D, C–D přátelé. F cizí všem.
insert into auth.users (id) select public.u(x) from unnest(array['0a', '0b', '0c', '0d', '0e', '0f']) x;
insert into public.profiles (id, username, display_name)
select public.u(x), 'user' || x, 'User ' || x from unnest(array['0a', '0b', '0c', '0d', '0e', '0f']) x;
insert into public.friendships (user_a, user_b, requested_by, status)
select least(public.u(a), public.u(b)), greatest(public.u(a), public.u(b)), public.u(a), 'accepted'
from (values ('0a', '0b'), ('0a', '0e'), ('0b', '0d'), ('0c', '0d')) v(a, b);
-- čekající žádost A → F se nepočítá
insert into public.friendships (user_a, user_b, requested_by, status)
values (least(public.u('0a'), public.u('0f')), greatest(public.u('0a'), public.u('0f')), public.u('0a'), 'pending');

-- 3 noci každého (karty ze stejné sekundy kvůli pořadí podle id)
insert into public.nights (user_id, night_date, sleep_start, sleep_end, total_sleep_min, score)
select public.u(x), current_date - g, now() - (g || ' days')::interval - interval '8 hours',
       now() - (g || ' days')::interval, 470, 80
from unnest(array['0a', '0b', '0c', '0d', '0e', '0f']) x, generate_series(0, 2) g;
insert into public.posts (kind, user_id, night_id, created_at)
select 'night', n.user_id, n.id, date_trunc('second', n.sleep_end) from public.nights n;

-- Výzvy: 1 duel C–D (A nevidí, B ano), 2 duel A–B, 3 skupinovka D+F s odmítnutým E.
insert into public.challenges (id, type, creator_id, duration_days, status) values
  ('40000000-0000-0000-0000-000000000001', 'duel', public.u('0c'), 7, 'finished'),
  ('40000000-0000-0000-0000-000000000002', 'duel', public.u('0a'), 7, 'finished'),
  ('40000000-0000-0000-0000-000000000003', 'free_for_all', public.u('0d'), 7, 'finished');
insert into public.challenge_participants (challenge_id, user_id, status) values
  ('40000000-0000-0000-0000-000000000001', public.u('0c'), 'accepted'),
  ('40000000-0000-0000-0000-000000000001', public.u('0d'), 'accepted'),
  ('40000000-0000-0000-0000-000000000002', public.u('0a'), 'accepted'),
  ('40000000-0000-0000-0000-000000000002', public.u('0b'), 'accepted'),
  ('40000000-0000-0000-0000-000000000003', public.u('0d'), 'accepted'),
  ('40000000-0000-0000-0000-000000000003', public.u('0f'), 'accepted'),
  ('40000000-0000-0000-0000-000000000003', public.u('0e'), 'declined');
insert into public.posts (kind, challenge_id, created_at)
select 'challenge_result', id, now() - interval '1 hour' from public.challenges;

set role authenticated;

-- =====================================================================
-- Kdo co vidí
-- =====================================================================
select t_as('0a');
select t_ok((select count(*) from public.feed_night_posts(30)) = 9, 'A: 9 nocí (já, B, E)');
select t_ok(not exists (select 1 from public.feed_night_posts(30) where user_id in (u('0c'), u('0d'), u('0f'))),
            'A: nic od C, D (přítel přítele) ani F (čekající žádost)');
select t_ok(array(select challenge_id from public.feed_result_posts(20)) = array['40000000-0000-0000-0000-000000000002'::uuid],
            'A: jen výsledek vlastního duelu (E výzvu odmítl, C–D nezná)');
select t_ok((select count(*) from public.feed_night_posts(2)) = 2, 'limit platí');
select t_ok((select count(*) from public.feed_night_posts(1000)) = 9, 'limit nad 100 se ořízne, nespadne');
select t_as('0b');
select t_ok((select count(*) from public.feed_result_posts(20)) = 3, 'B: výsledky přes sebe i přes D (oba duely + skupinovka)');

select t_same(x) from unnest(array['0a', '0b', '0c', '0d', '0e', '0f']) x;

-- =====================================================================
-- Nahlášení, automatické skrytí, blok – RLS platí i v RPC
-- =====================================================================
select t_as('0a');
select public.report_content('post', (select id from public.posts where user_id = u('0b') order by created_at desc limit 1), 'spam');
select t_ok((select count(*) from public.feed_night_posts(30) where user_id = u('0b')) = 2, 'A: nahlášenou kartu B už nevidí');

reset role;
update public.posts set hidden_at = now()
where id = (select id from public.posts where user_id = u('0e') order by created_at desc limit 1);
set role authenticated;
select t_ok((select count(*) from public.feed_night_posts(30) where user_id = u('0e')) = 2, 'A: skrytou kartu E nevidí');
select t_as('0e');
select t_ok((select count(*) from public.feed_night_posts(30) where user_id = u('0e')) = 3, 'E: svoji skrytou kartu vidí');

select t_as('0d');
select public.block_user(u('0b'));
select t_ok(not exists (select 1 from public.feed_night_posts(30) where user_id = u('0b')), 'D: po bloku karty B zmizí');

select t_same(x) from unnest(array['0a', '0b', '0c', '0d', '0e', '0f']) x;

select t_as('0f');
reset role;
-- anon nemá přístup
set role anon;
do $$ begin
  perform public.feed_night_posts(30);
  raise exception 'FAIL: anon spustil feed_night_posts';
exception when insufficient_privilege then raise notice 'ok  anon nemá feed_night_posts';
end $$;
reset role;

-- =====================================================================
-- Výkon: 40 000 karet cizích lidí, F má jediného kamaráda bez karet
-- =====================================================================
insert into auth.users (id) select gen_random_uuid() from generate_series(1, 200);
insert into public.profiles (id, username, display_name)
select id, 'x' || substr(id::text, 1, 8), 'X' from auth.users where id::text not like '00000000-0000-0000-0000-0000000000%';
insert into public.nights (user_id, night_date, sleep_start, sleep_end, total_sleep_min, score)
select p.id, current_date - g, now() - (g || ' days')::interval - interval '8 hours', now() - (g || ' days')::interval, 470, 70
from public.profiles p, generate_series(3, 202) g where p.username like 'x%';
insert into public.posts (kind, user_id, night_id, created_at)
select 'night', n.user_id, n.id, n.sleep_end from public.nights n where n.score = 70;
analyze;

set role authenticated;
select t_as('0c');
do $$
declare t0 timestamptz; ms_old numeric; ms_new numeric; ms_res_old numeric; ms_res_new numeric;
begin
  t0 := clock_timestamp();
  perform count(*) from (select id from public.posts where kind = 'night' order by created_at desc limit 30) s;
  ms_old := extract(epoch from clock_timestamp() - t0) * 1000;
  t0 := clock_timestamp();
  perform count(*) from public.feed_night_posts(30);
  ms_new := extract(epoch from clock_timestamp() - t0) * 1000;
  t0 := clock_timestamp();
  perform count(*) from (select id from public.posts where kind = 'challenge_result' order by created_at desc limit 20) s;
  ms_res_old := extract(epoch from clock_timestamp() - t0) * 1000;
  t0 := clock_timestamp();
  perform count(*) from public.feed_result_posts(20);
  ms_res_new := extract(epoch from clock_timestamp() - t0) * 1000;
  raise notice 'čas (40k karet, C má 1 kamaráda): noci % → % ms, výsledky % → % ms',
    round(ms_old), round(ms_new), round(ms_res_old), round(ms_res_new);
  perform public.t_ok(ms_new < 50 and ms_res_new < 50, 'RPC nečte celou tabulku (< 50 ms)');
end $$;
select t_same(x) from unnest(array['0a', '0b', '0c']) x;
