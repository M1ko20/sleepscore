-- Lokální test: „X tě předbíhá“ ve výzvě a komentáře pro celé vlákno (issue #15).
-- Spuštění: supabase/tests/local/run.sh supabase/tests/local/notifications_overtake_threads_test.sql
\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on

create function pg_temp.ok(label text, got anyelement, expected anyelement) returns void language plpgsql as $$
begin
  if got is distinct from expected then
    raise exception 'FAIL %: got %, expected %', label, got, expected;
  end if;
  raise notice 'ok  %', label;
end $$;
create function pg_temp.u(x text) returns uuid language sql immutable as $$
  select ('00000000-0000-0000-0000-00000000000' || x)::uuid $$;
create function pg_temp.cnt(x text, k text) returns int language sql as $$
  select count(*)::int from public.notifications where user_id = pg_temp.u(x) and kind = k $$;
create function pg_temp.text_of(x text, k text) returns text language sql as $$
  select public.notification_text(n) from public.notifications n
  where n.user_id = pg_temp.u(x) and n.kind = k order by created_at desc, id limit 1 $$;
create function pg_temp.friends(x text, y text) returns void language sql as $$
  insert into public.friendships (user_a, user_b, requested_by, status)
  values (least(pg_temp.u(x), pg_temp.u(y)), greatest(pg_temp.u(x), pg_temp.u(y)), pg_temp.u(x), 'accepted') $$;
-- „dnes“ v pásmu zakladatele (všichni Europe/Prague)
create function pg_temp.t(off int default 0) returns date language sql as $$
  select (now() at time zone 'Europe/Prague')::date + off $$;

insert into auth.users (id) select pg_temp.u(x) from unnest(array['a','b','c','d','e','f','9']) x;
insert into public.profiles (id, username, display_name) values
  (pg_temp.u('a'), 'adam', 'Adam'), (pg_temp.u('b'), 'bara', 'Bára'), (pg_temp.u('c'), 'cyril', 'Cyril'),
  (pg_temp.u('d'), 'dana', 'Dana'), (pg_temp.u('e'), 'eva', 'Eva'), (pg_temp.u('f'), 'filip', 'Filip'),
  (pg_temp.u('9'), 'gita', 'Gita');
select pg_temp.friends('a', x) from unnest(array['b','c','d','e','f','9']) x;
select pg_temp.friends('b', 'c');

-- =====================================================================
-- Komentáře ve vlákně
-- =====================================================================
insert into public.nights (id, user_id, night_date, sleep_start, sleep_end, total_sleep_min, score) values
  ('10000000-0000-0000-0000-000000000001', pg_temp.u('a'), pg_temp.t(-20),
   now() - interval '20 days 9 hours', now() - interval '20 days 1 hour', 450, 80);
insert into public.posts (id, kind, user_id, night_id) values
  ('20000000-0000-0000-0000-000000000001', 'night', pg_temp.u('a'), '10000000-0000-0000-0000-000000000001');
create function pg_temp.comment(x text, body text) returns void language sql as $$
  insert into public.comments (post_id, user_id, body) values ('20000000-0000-0000-0000-000000000001', pg_temp.u(x), body) $$;

select pg_temp.comment('b', 'a já měla 88');
select pg_temp.ok('autor karty', pg_temp.text_of('a', 'comment'), 'Bára komentuje tvoji noc: a já měla 88');
select pg_temp.ok('první komentář – nikdo další', (select count(*)::int from public.notifications where kind = 'comment'), 1);
select pg_temp.ok('payload autora bez thread', (select payload ? 'thread' from public.notifications where user_id = pg_temp.u('a') and kind = 'comment'), false);

select pg_temp.comment('c', 'jak dřevo');
select pg_temp.ok('autor karty 2', pg_temp.cnt('a', 'comment'), 2);
select pg_temp.ok('vlákno – předchozí komentující', pg_temp.text_of('b', 'comment'), 'Cyril taky komentuje noc, kterou má Adam: jak dřevo');
select pg_temp.ok('vlákno – autor komentáře nic', pg_temp.cnt('c', 'comment'), 0);
select pg_temp.ok('vlákno – kategorie', (select category from public.notifications where user_id = pg_temp.u('b') and kind = 'comment'), 'comments');

select pg_temp.comment('a', 'díky');
select pg_temp.ok('autor karty odpovídá – B', pg_temp.text_of('b', 'comment'), 'Adam odpovídá pod svojí nocí: díky');
select pg_temp.ok('autor karty odpovídá – C', pg_temp.text_of('c', 'comment'), 'Adam odpovídá pod svojí nocí: díky');
select pg_temp.ok('autor karty sám sobě nic', pg_temp.cnt('a', 'comment'), 2);

select pg_temp.comment('b', 'ještě jednou');
select pg_temp.ok('opakovaný komentující – jen 1 notifikace na komentář (C)', pg_temp.cnt('c', 'comment'), 2);
select pg_temp.ok('opakovaný komentující – sám sobě nic', pg_temp.cnt('b', 'comment'), 2);
select pg_temp.ok('autor karty dostane', pg_temp.cnt('a', 'comment'), 3);

-- D napíše, pak má blok s C; E napíše a pak přestane být přítel A;
-- F napíše a kartu nahlásí; G napíše a je zabanovaná.
select pg_temp.comment('d', 'd');
select pg_temp.comment('e', 'e');
select pg_temp.comment('f', 'f');
select pg_temp.comment('9', '9');
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.u('c'), pg_temp.u('d'));
delete from public.friendships where user_a = least(pg_temp.u('a'), pg_temp.u('e')) and user_b = greatest(pg_temp.u('a'), pg_temp.u('e'));
insert into public.reports (reporter_id, target_kind, target_id, reported_user_id, reason, snapshot)
values (pg_temp.u('f'), 'post', '20000000-0000-0000-0000-000000000001', pg_temp.u('a'), 'spam', '{}');
update public.profiles set banned_at = now() where id = pg_temp.u('9');
delete from public.notifications;

select pg_temp.comment('d', 'od Dany');
select pg_temp.ok('blok – C od D nic', pg_temp.cnt('c', 'comment'), 0);
select pg_temp.ok('nepřítel autora karty nic', pg_temp.cnt('e', 'comment'), 0);
select pg_temp.ok('nahlásil kartu – nic', pg_temp.cnt('f', 'comment'), 0);
select pg_temp.ok('zabanovaný nic', pg_temp.cnt('9', 'comment'), 0);
select pg_temp.ok('ostatní dostanou (A, B)', (select string_agg(p.username, ',' order by p.username)
  from public.notifications n join public.profiles p on p.id = n.user_id), 'adam,bara');
select pg_temp.comment('c', 'od Cyrila');
select pg_temp.ok('blok – D od C nic', pg_temp.cnt('d', 'comment'), 0);
select pg_temp.ok('B dostane od C', pg_temp.text_of('b', 'comment'), 'Cyril taky komentuje noc, kterou má Adam: od Cyrila');

-- kartu už nevidím (text čte jako příjemce) → bez jména
select set_config('request.jwt.claim.sub', pg_temp.u('b')::text, false);
delete from public.friendships where user_a = least(pg_temp.u('a'), pg_temp.u('b')) and user_b = greatest(pg_temp.u('a'), pg_temp.u('b'));
set role authenticated;
select pg_temp.ok('karta už neviditelná → bez jména',
  (select public.notification_text(n) from public.notifications n where n.kind = 'comment' order by created_at desc limit 1),
  'Cyril taky komentuje: od Cyrila');
reset role;
select pg_temp.friends('a', 'b');
delete from public.notifications;

-- =====================================================================
-- „X tě předbíhá“
-- =====================================================================
-- noci pro night_id (dny t-3 … t)
insert into public.nights (user_id, night_date, sleep_start, sleep_end, total_sleep_min, score)
select pg_temp.u(x), pg_temp.t(d), now() - make_interval(days => -d), now() - make_interval(days => -d) + interval '8 hours', 480, 70
from unnest(array['a','b','c','d']) x, generate_series(-3, 0) d;
create function pg_temp.night(x text, off int) returns uuid language sql as $$
  select id from public.nights where user_id = pg_temp.u(x) and night_date = pg_temp.t(off) $$;
create function pg_temp.score(ch uuid, x text, off int, s int) returns void language sql as $$
  insert into public.challenge_day_scores (challenge_id, user_id, day, score, night_id)
  values (ch, pg_temp.u(x), pg_temp.t(off), s, pg_temp.night(x, off))
  on conflict (challenge_id, user_id, day) do update set score = excluded.score, night_id = excluded.night_id $$;
create function pg_temp.challenge(id uuid, typ text, users text[], start_off int, target int default null) returns void language sql as $$
  insert into public.challenges (id, type, creator_id, duration_days, start_date, end_date, status, target_score)
  values (id, typ::public.challenge_type, pg_temp.u(users[1]), 7, pg_temp.t(start_off), pg_temp.t(start_off + 6), 'active', target);
  insert into public.challenge_participants (challenge_id, user_id, status)
  select id, pg_temp.u(x), 'accepted' from unnest(users) x $$;

-- Duel A × B, den 4/7
select pg_temp.challenge('50000000-0000-0000-0000-000000000001', 'duel', array['a','b'], -3);
select pg_temp.score('50000000-0000-0000-0000-000000000001', 'a', d, 75) from generate_series(-3, -1) d;
select pg_temp.score('50000000-0000-0000-0000-000000000001', 'b', d, 70) from generate_series(-3, -1) d;
select pg_temp.ok('rozjezd bez notifikací', (select count(*)::int from public.notifications), 0);
select pg_temp.ok('průběžný průměr (dnešek ještě není)',
  round(private.challenge_running_avg('50000000-0000-0000-0000-000000000001', pg_temp.u('a'), pg_temp.t()), 2), 75.00);

select pg_temp.score('50000000-0000-0000-0000-000000000001', 'b', 0, 100);   -- B: 310/4 = 77,5 > A 75
select pg_temp.ok('B předbíhá A', pg_temp.text_of('a', 'challenge_overtaken'), 'Bára tě předbíhá v souboji. 77,5 : 75,0.');
select pg_temp.ok('B sám sobě nic', pg_temp.cnt('b', 'challenge_overtaken'), 0);
select pg_temp.ok('kategorie challenges', (select category from public.notifications where kind = 'challenge_overtaken'), 'challenges');
select pg_temp.ok('proklik na výzvu', (select challenge_id from public.notifications where kind = 'challenge_overtaken'),
  '50000000-0000-0000-0000-000000000001'::uuid);

select pg_temp.score('50000000-0000-0000-0000-000000000001', 'a', 0, 60);    -- A: 285/4 = 71,25, pořád za B
select pg_temp.ok('A pořád za – nic', pg_temp.cnt('b', 'challenge_overtaken'), 0);
select pg_temp.score('50000000-0000-0000-0000-000000000001', 'a', 0, 100);   -- přepis: 325/4 = 81,25
select pg_temp.ok('přepis skóre – A předbíhá B', pg_temp.text_of('b', 'challenge_overtaken'), 'Adam tě předbíhá v souboji. 81,3 : 77,5.');

select pg_temp.score('50000000-0000-0000-0000-000000000001', 'b', 0, 100);   -- opakovaný sync, stejné skóre
select pg_temp.ok('stejné skóre nic', (select count(*)::int from public.notifications), 2);
select pg_temp.score('50000000-0000-0000-0000-000000000001', 'b', -1, 100);  -- zpětně: B 85 > A 81,25
select pg_temp.ok('max. 1 za den a výzvu', pg_temp.cnt('a', 'challenge_overtaken'), 1);
select pg_temp.ok('první zůstane beze změny', pg_temp.text_of('a', 'challenge_overtaken'), 'Bára tě předbíhá v souboji. 77,5 : 75,0.');
-- zítra by šla další (simulace: posunout den v payloadu)
update public.notifications set payload = payload || jsonb_build_object('day', pg_temp.t(-1)) where kind = 'challenge_overtaken';
select pg_temp.score('50000000-0000-0000-0000-000000000001', 'a', -1, 100);  -- A: 350/4 = 87,5 > B 85
select pg_temp.ok('další den znovu', pg_temp.cnt('b', 'challenge_overtaken'), 2);

-- Nuly bez noci (uzavírání) nic neposílají
delete from public.notifications;
insert into public.challenge_day_scores (challenge_id, user_id, day, score)
values ('50000000-0000-0000-0000-000000000001', pg_temp.u('b'), pg_temp.t(1), 0);
select pg_temp.ok('nula bez noci nic', (select count(*)::int from public.notifications), 0);

-- Všichni proti všem A, B, C, D (D má blok s A)
select pg_temp.challenge('50000000-0000-0000-0000-000000000002', 'free_for_all', array['b','a','c','d'], -3);
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.u('d'), pg_temp.u('a'));
select pg_temp.score('50000000-0000-0000-0000-000000000002', x, d, case x when 'a' then 60 else 80 end)
from unnest(array['a','b','c','d']) x, generate_series(-3, -1) d;
delete from public.notifications;
select pg_temp.score('50000000-0000-0000-0000-000000000002', 'a', -1, 100);  -- A: 220/3 = 73,3, pořád za
select pg_temp.ok('FFA – pořád za', (select count(*)::int from public.notifications), 0);
select pg_temp.score('50000000-0000-0000-0000-000000000002', 'a', -2, 100);
select pg_temp.score('50000000-0000-0000-0000-000000000002', 'a', -3, 100);  -- A: 260/3 = 86,7 > 80 hned po -2
select pg_temp.ok('FFA – B', pg_temp.text_of('b', 'challenge_overtaken'), 'Adam tě předbíhá ve výzvě. 86,7 : 80,0.');
select pg_temp.ok('FFA – C (jen 1 i po dalším zlepšení)', pg_temp.cnt('c', 'challenge_overtaken'), 1);
select pg_temp.ok('FFA – blok D nic', pg_temp.cnt('d', 'challenge_overtaken'), 0);

-- Společný cíl: nic
delete from public.notifications;
select pg_temp.challenge('50000000-0000-0000-0000-000000000003', 'team_goal', array['a','b','c'], -3, 80);
select pg_temp.score('50000000-0000-0000-0000-000000000003', 'b', -1, 50);
select pg_temp.score('50000000-0000-0000-0000-000000000003', 'a', -1, 90);
select pg_temp.ok('společný cíl nic', (select count(*)::int from public.notifications), 0);

-- Po uzávěrce (poslední den včera, výzva ještě nezfinalizovaná): nic
select pg_temp.challenge('50000000-0000-0000-0000-000000000004', 'duel', array['a','b'], -7);
select pg_temp.score('50000000-0000-0000-0000-000000000004', 'b', -3, 50);
select pg_temp.score('50000000-0000-0000-0000-000000000004', 'a', -3, 90);
select pg_temp.ok('po uzávěrce nic', (select count(*)::int from public.notifications), 0);

-- Text: shoda na 1 desetinné místo → 2 místa
insert into public.notifications (user_id, kind, actor_id, challenge_id, payload)
values (pg_temp.u('c'), 'challenge_overtaken', pg_temp.u('a'), '50000000-0000-0000-0000-000000000002',
        '{"type": "free_for_all", "day": "2000-01-01", "actor_avg": 80.04, "my_avg": 80.01}');
select pg_temp.ok('text 2 desetinná místa', pg_temp.text_of('c', 'challenge_overtaken'), 'Adam tě předbíhá ve výzvě. 80,04 : 80,01.');

select 'ALL OK';
