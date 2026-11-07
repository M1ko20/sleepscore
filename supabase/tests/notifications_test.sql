-- Lokální test notifikací (issue #9). Spuštění: supabase/tests/local/run.sh supabase/tests/notifications_test.sql
-- Čistá DB se stuby Supabase + všechny migrace; každá kontrola při chybě skončí výjimkou.
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
create function pg_temp.as_user(x text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', pg_temp.u(x)::text, false) $$;
-- texty notifikací příjemce (nejnovější první)
create function pg_temp.texts(x text) returns text language sql as $$
  select coalesce(string_agg(public.notification_text(n), ' | ' order by n.created_at desc, n.kind), '')
  from public.notifications n where n.user_id = pg_temp.u(x) $$;
create function pg_temp.cnt(x text, k text) returns int language sql as $$
  select count(*)::int from public.notifications where user_id = pg_temp.u(x) and kind = k $$;
create function pg_temp.text_of(x text, k text) returns text language sql as $$
  select public.notification_text(n) from public.notifications n
  where n.user_id = pg_temp.u(x) and n.kind = k order by created_at desc limit 1 $$;
grant execute on all functions in schema pg_temp to authenticated;

insert into auth.users select pg_temp.u(x) from unnest(array['a','b','c','d']) x;
insert into public.profiles (id, username, display_name) values
  (pg_temp.u('a'), 'adam', 'Adam'), (pg_temp.u('b'), 'bara', 'Bára'),
  (pg_temp.u('c'), 'cyril', 'Cyril'), (pg_temp.u('d'), 'dana', 'Dana');
insert into public.user_stats (user_id) select id from public.profiles;

-- ===== Přátelství ======================================================
-- pozvánka: A → B (redeem_invite udělá rovnou přátelství)
delete from public.profiles where id = pg_temp.u('b');
insert into public.invites (code, inviter_id) values ('TESTCODE', pg_temp.u('a'));
select pg_temp.as_user('b');
set role authenticated;
select (public.redeem_invite('TESTCODE', 'bara', 'Bára')).username;
reset role;
select pg_temp.ok('invite → zvoucímu', pg_temp.text_of('a', 'friend_accepted'), 'Bára je tu přes tvoji pozvánku.');
select pg_temp.ok('invite → pozvanému nic', pg_temp.cnt('b', 'friend_accepted'), 0);

-- žádost C → A, A přijme
select pg_temp.as_user('c');
set role authenticated;
select public.send_friend_request(pg_temp.u('a'));
reset role;
select pg_temp.ok('žádost', pg_temp.text_of('a', 'friend_request'), 'Cyril ti posílá žádost o přátelství.');
select pg_temp.as_user('a');
set role authenticated;
select public.respond_friend_request(pg_temp.u('c'), true);
reset role;
select pg_temp.ok('přijatá žádost', pg_temp.text_of('c', 'friend_accepted'), 'Adam přijímá žádost o přátelství.');
select pg_temp.ok('přijetí – žádost zůstane v historii', pg_temp.cnt('a', 'friend_request'), 1);

-- žádost D → A, D ji stáhne → zmizí
select pg_temp.as_user('d');
set role authenticated;
select public.send_friend_request(pg_temp.u('a'));
reset role;
select pg_temp.ok('žádost D', pg_temp.cnt('a', 'friend_request'), 2);
select pg_temp.as_user('d');
set role authenticated;
select public.remove_friend(pg_temp.u('a'));
reset role;
select pg_temp.ok('stažená žádost zmizí', pg_temp.cnt('a', 'friend_request'), 1);

-- ===== Ranní karta =====================================================
insert into public.nights (id, user_id, night_date, sleep_start, sleep_end, total_sleep_min, score) values
  ('10000000-0000-0000-0000-000000000001', pg_temp.u('a'), (now() at time zone 'Europe/Prague')::date,
   now() - interval '9 hours', now() - interval '1 hour', 450, 80),
  ('10000000-0000-0000-0000-000000000002', pg_temp.u('a'), (now() at time zone 'Europe/Prague')::date - 10,
   now() - interval '10 days 9 hours', now() - interval '10 days 1 hour', 450, 70);
insert into public.posts (id, kind, user_id, night_id) values
  ('20000000-0000-0000-0000-000000000001', 'night', pg_temp.u('a'), '10000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002', 'night', pg_temp.u('a'), '10000000-0000-0000-0000-000000000002');
select pg_temp.ok('ranní karta jen čerstvá', pg_temp.cnt('a', 'night_ready'), 1);
select pg_temp.ok('ranní karta text', pg_temp.text_of('a', 'night_ready'), 'Tvoje noc: 80. Doplň komentář.');
update public.posts set body = 'jak dřevo' where id = '20000000-0000-0000-0000-000000000001';
select pg_temp.ok('ranní karta po doplnění', pg_temp.text_of('a', 'night_ready'), 'Tvoje noc: 80.');

-- ===== Reakce ==========================================================
create function pg_temp.react(x text, k text) returns void language sql as $$
  insert into public.reactions (post_id, user_id, kind)
  values ('20000000-0000-0000-0000-000000000001', pg_temp.u(x), k::public.reaction_kind)
  on conflict (post_id, user_id) do update set kind = excluded.kind $$;
create function pg_temp.unreact(x text) returns void language sql as $$
  delete from public.reactions where post_id = '20000000-0000-0000-0000-000000000001' and user_id = pg_temp.u(x) $$;

select pg_temp.react('b', 'sleeper');
select pg_temp.ok('reakce 1', pg_temp.text_of('a', 'reaction'), 'Bára reaguje na tvoji noc.');
select pg_temp.react('c', 'beer');
select pg_temp.ok('reakce sloučené', pg_temp.cnt('a', 'reaction'), 1);
select pg_temp.ok('reakce 2', pg_temp.text_of('a', 'reaction'), 'Cyril a 1 další reagují na tvoji noc.');
select pg_temp.react('a', 'crown');
select pg_temp.ok('vlastní reakce se nepočítá', (select count from public.notifications where user_id = pg_temp.u('a') and kind = 'reaction'), 2);

select pg_temp.as_user('a');
set role authenticated;
select pg_temp.ok('mark read', public.mark_notifications_read() > 0, true);
reset role;
select pg_temp.react('b', 'zombie');   -- změna druhu = nic
select pg_temp.ok('změna reakce nic nepošle', (select read_at is not null from public.notifications where user_id = pg_temp.u('a') and kind = 'reaction'), true);
select pg_temp.unreact('c');
select pg_temp.ok('smazaná reakce odečte', pg_temp.text_of('a', 'reaction'), 'Bára reaguje na tvoji noc.');
select pg_temp.ok('odečtení nechá přečtené', (select read_at is not null from public.notifications where user_id = pg_temp.u('a') and kind = 'reaction'), true);
select pg_temp.react('d', 'coffee');   -- D není přítel, ale test běží jako postgres – jde o počítání
select pg_temp.react('c', 'beer');
select pg_temp.ok('nová reakce = znovu nepřečtené', (select read_at is null from public.notifications where user_id = pg_temp.u('a') and kind = 'reaction'), true);
select pg_temp.ok('3 reagující', pg_temp.text_of('a', 'reaction'), 'Cyril a 2 další reagují na tvoji noc.');
select pg_temp.unreact('b'); select pg_temp.unreact('c'); select pg_temp.unreact('d');
select pg_temp.ok('poslední smazaná reakce smaže notifikaci', pg_temp.cnt('a', 'reaction'), 0);

-- ===== Komentáře =======================================================
insert into public.comments (id, post_id, user_id, body) values
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', pg_temp.u('b'), 'a já měla 88'),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', pg_temp.u('a'), 'gratuluju');
select pg_temp.ok('komentář', pg_temp.texts('a') like 'Bára komentuje tvoji noc: a já měla 88%', true);
select pg_temp.ok('vlastní komentář nic', pg_temp.cnt('a', 'comment'), 1);
select pg_temp.ok('odpověď autora karty ve vlákně', pg_temp.text_of('b', 'comment'), 'Adam odpovídá pod svojí nocí: gratuluju');
delete from public.comments where id = '30000000-0000-0000-0000-000000000001';
select pg_temp.ok('smazaný komentář', pg_temp.cnt('a', 'comment'), 0);

-- ===== Duel: pozvánka, start, výsledek, dluh, odznak ===================
select pg_temp.as_user('a');
set role authenticated;
select public.create_challenge('duel', array[pg_temp.u('b')], 7, 'pivo') as duel \gset
reset role;
select pg_temp.ok('pozvánka do duelu', pg_temp.text_of('b', 'challenge_invite'), 'Adam tě vyzývá: 7 dní, pivo.');
select pg_temp.ok('zakladatel nic', pg_temp.cnt('a', 'challenge_invite'), 0);
select pg_temp.as_user('b');
set role authenticated;
select public.respond_challenge(:'duel', true);
reset role;
select pg_temp.ok('přijatý duel = start zakladateli', pg_temp.text_of('a', 'challenge_started'),
  'Bára výzvu přijímá. Start ' || to_char((now() at time zone 'Europe/Prague')::date + 1, 'FMDD. FMMM.') || ', 7 dní.');
select pg_temp.ok('duel – žádná zvláštní odpověď', pg_temp.cnt('a', 'challenge_response'), 0);
select pg_temp.ok('kdo přijal, nedostane start', pg_temp.cnt('b', 'challenge_started'), 0);

update public.challenges set start_date = current_date - 10, end_date = current_date - 4 where id = :'duel';
insert into public.challenge_day_scores (challenge_id, user_id, day, score, night_id)
select :'duel', u, d::date, case when u = pg_temp.u('a') then 80 else 70 end, null
from unnest(array[pg_temp.u('a'), pg_temp.u('b')]) u, generate_series(current_date - 10, current_date - 4, '1 day') d;
select private.finalize_challenge(:'duel');
select pg_temp.ok('výhra', pg_temp.text_of('a', 'challenge_result'), 'Vyhráno 80,0 : 70,0. Bára přichází o duši.');
select pg_temp.ok('prohra', pg_temp.text_of('b', 'challenge_result'), 'Prohra 70,0 : 80,0. Adam bere tvoji duši.');
-- (day scores bez night_id = „chybějící noc“ → oba mají i Zapomněl hodinky)
select pg_temp.ok('odznak za výhru', (select public.notification_text(n) from public.notifications n
  where n.user_id = pg_temp.u('a') and n.kind = 'achievement' and n.payload ->> 'code' = 'first_soul'), 'Nový odznak: První duše.');
select pg_temp.ok('odznak → výzva', (select challenge_id from public.notifications where user_id = pg_temp.u('a')
  and kind = 'achievement' and payload ->> 'code' = 'first_soul'), :'duel'::uuid);

select pg_temp.as_user('b');
set role authenticated;
select public.settle_debt((select id from public.debts where challenge_id = :'duel'));
reset role;
select pg_temp.ok('dluh splacen', pg_temp.text_of('a', 'debt_settled'), 'Bára hlásí splaceno: pivo.');

-- ===== Všichni proti všem: odpovědi a start skupiny ====================
-- C je přítel A, B je přítel A
select pg_temp.as_user('a');
set role authenticated;
select public.create_challenge('free_for_all', array[pg_temp.u('b'), pg_temp.u('c')], 14) as ffa \gset
reset role;
select pg_temp.ok('pozvánka skupina', pg_temp.text_of('c', 'challenge_invite'), 'Adam tě zve do výzvy všichni proti všem: 14 dní.');
select pg_temp.as_user('b'); set role authenticated; select public.respond_challenge(:'ffa', true); reset role;
select pg_temp.as_user('c'); set role authenticated; select public.respond_challenge(:'ffa', true); reset role;
select pg_temp.ok('odpovědi zakladateli', pg_temp.cnt('a', 'challenge_response'), 2);
select pg_temp.ok('odpověď text', pg_temp.text_of('a', 'challenge_response') in ('Bára jde do toho.', 'Cyril jde do toho.'), true);
select pg_temp.as_user('a'); set role authenticated; select public.start_challenge(:'ffa'); reset role;
select pg_temp.ok('start skupiny hráčům', pg_temp.cnt('b', 'challenge_started') + pg_temp.cnt('c', 'challenge_started'), 2);
select pg_temp.ok('start skupiny ne zakladateli', pg_temp.cnt('a', 'challenge_started'), 1);   -- jen ten z duelu
select pg_temp.ok('start text', pg_temp.text_of('c', 'challenge_started'),
  'Výzva startuje ' || to_char((now() at time zone 'Europe/Prague')::date + 1, 'FMDD. FMMM.') || '. 14 dní.');

-- odmítnutí skupinové pozvánky
select pg_temp.as_user('a');
set role authenticated;
select public.create_challenge('team_goal', array[pg_temp.u('b'), pg_temp.u('c')], 7, null, 85::smallint) as team \gset
reset role;
select pg_temp.ok('pozvánka společný cíl', pg_temp.text_of('b', 'challenge_invite'), 'Adam tě zve do společného cíle 85: 7 dní.');
select pg_temp.as_user('b'); set role authenticated; select public.respond_challenge(:'team', false); reset role;
select pg_temp.ok('odmítnutí', pg_temp.text_of('a', 'challenge_response'), 'Bára výzvu odmítá.');

-- ===== Zítra konec (pg_cron, 20:00 místního času) ======================
insert into public.challenges (id, type, creator_id, stake, duration_days, start_date, end_date, status)
values ('40000000-0000-0000-0000-000000000001', 'duel', pg_temp.u('a'), 'večeře', 7, '2026-11-05', '2026-11-11', 'active');
insert into public.challenge_participants (challenge_id, user_id, status) values
  ('40000000-0000-0000-0000-000000000001', pg_temp.u('a'), 'accepted'),
  ('40000000-0000-0000-0000-000000000001', pg_temp.u('c'), 'accepted');
insert into public.challenge_day_scores (challenge_id, user_id, day, score)
select '40000000-0000-0000-0000-000000000001'::uuid, pg_temp.u('a'), d::date, 80 from generate_series('2026-11-05'::date, '2026-11-09', '1 day') d
union all
select '40000000-0000-0000-0000-000000000001'::uuid, pg_temp.u('c'), d::date, 75 from generate_series('2026-11-05'::date, '2026-11-10', '1 day') d;
select pg_temp.ok('zítra konec – mimo 20:00 nic',
  private.notify_challenges_ending('2026-11-10 19:30'::timestamp at time zone 'Europe/Prague'), 0);
select pg_temp.ok('zítra konec – 20:00',
  private.notify_challenges_ending('2026-11-10 20:10'::timestamp at time zone 'Europe/Prague'), 2);
select pg_temp.ok('zítra konec – jen jednou',
  private.notify_challenges_ending('2026-11-10 20:50'::timestamp at time zone 'Europe/Prague'), 0);
select pg_temp.ok('prohrávám', pg_temp.text_of('a', 'challenge_ending'), 'Zítra konec. Prohráváš o 8,3 bodu.');
select pg_temp.ok('vedu', pg_temp.text_of('c', 'challenge_ending'), 'Zítra konec. Vedeš o 8,3 bodu.');

-- ===== Pondělní recap ==================================================
insert into public.nights (user_id, night_date, sleep_start, sleep_end, total_sleep_min, score) values
  (pg_temp.u('a'), '2030-03-05', '2030-03-04 22:00+01', '2030-03-05 06:00+01', 480, 80),
  (pg_temp.u('a'), '2030-03-06', '2030-03-05 22:00+01', '2030-03-06 06:00+01', 480, 70);
select pg_temp.ok('recap mimo pondělí 9:00 nic',
  private.notify_weekly_recaps('2030-03-11 08:30'::timestamp at time zone 'Europe/Prague'), 0);
select pg_temp.ok('recap pondělí 9:00 (jen kdo spal)',
  private.notify_weekly_recaps('2030-03-11 09:15'::timestamp at time zone 'Europe/Prague'), 1);
select pg_temp.ok('recap jen jednou',
  private.notify_weekly_recaps('2030-03-11 09:45'::timestamp at time zone 'Europe/Prague'), 0);
select pg_temp.ok('recap text', pg_temp.text_of('a', 'weekly_recap'), 'Minulý týden v číslech: průměr 75, 2 noci.');

-- ===== Opakovaný odznak ================================================
select private.award(pg_temp.u('a'), 'deep_diver', '10000000-0000-0000-0000-000000000002');
select private.award(pg_temp.u('a'), 'deep_diver', '10000000-0000-0000-0000-000000000001');
select pg_temp.ok('opakovaný odznak', pg_temp.text_of('a', 'achievement'), 'Hlubinář. Zase.');
select pg_temp.ok('odznak → karta', (select post_id from public.notifications where user_id = pg_temp.u('a')
  and kind = 'achievement' and payload ->> 'code' = 'deep_diver' and (payload ->> 'times')::int = 2),
  '20000000-0000-0000-0000-000000000001'::uuid);

-- ===== RLS a práva =====================================================
select pg_temp.as_user('b');
set role authenticated;
select pg_temp.ok('vidím jen svoje', (select bool_and(user_id = pg_temp.u('b')) from public.notifications), true);
select pg_temp.ok('nepřečtené před', (select count(*)::int from public.notifications where read_at is null) > 0, true);
select public.mark_notifications_read();
select pg_temp.ok('otevření = vše přečtené', (select count(*)::int from public.notifications where read_at is null), 0);
do $$ begin
  insert into public.notifications (user_id, kind) values (auth.uid(), 'comment');
  raise exception 'FAIL insert z klienta prošel';
exception when insufficient_privilege then raise notice 'ok  insert z klienta zakázán';
end $$;
do $$ begin
  update public.notifications set read_at = null;
  raise exception 'FAIL update z klienta prošel';
exception when insufficient_privilege then raise notice 'ok  update z klienta zakázán';
end $$;
reset role;

-- ===== Smazaný účet aktéra, úklid ======================================
delete from auth.users where id = pg_temp.u('c');
-- přijatá žádost od C zůstává v historii, C už není → „Někdo“
select pg_temp.ok('aktér smazaný → „Někdo“', (select public.notification_text(n) from public.notifications n
  where n.user_id = pg_temp.u('a') and n.kind = 'friend_request'), 'Někdo ti posílá žádost o přátelství.');
select pg_temp.ok('kategorie', (select string_agg(distinct category, ',' order by category) from public.notifications),
  'achievements,challenges,comments,friends,morning,recap');
update public.notifications set created_at = now() - interval '31 days' where kind = 'weekly_recap';
select pg_temp.ok('úklid 30 dní', private.cleanup_notifications(), 1);
select pg_temp.ok('cron úlohy', (select count(*)::int from cron.job where jobname in ('notification-jobs', 'notifications-cleanup')), 2);

select 'ALL OK';
