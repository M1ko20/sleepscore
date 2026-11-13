-- Pravidla z review (#37): kontumace, přepočet odznaků, vzájemná bilance,
-- délka a vypršení výzev, milník série jednou. Spouští run.sh.
\set ON_ERROR_STOP 1

create function pg_temp.ok(msg text, got anyelement, want anyelement) returns void language plpgsql as $$
begin
  if got is distinct from want then raise exception 'FAIL: % (čekal jsem %, přišlo %)', msg, want, got; end if;
  raise notice 'ok  %', msg;
end;
$$;
create function pg_temp.err(msg text, p_sql text, p_expect text) returns void language plpgsql as $$
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
create function pg_temp.u(x text) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-00000000000' || x)::uuid $$;
create function pg_temp.today() returns date language sql as $$ select (now() at time zone 'Europe/Prague')::date $$;

insert into auth.users (id) values (pg_temp.u('a')), (pg_temp.u('b')), (pg_temp.u('c')), (pg_temp.u('d'));
insert into public.profiles (id, username, display_name) values
  (pg_temp.u('a'), 'adam', 'Adam'), (pg_temp.u('b'), 'bara', 'Bára'),
  (pg_temp.u('c'), 'cyril', 'Cyril'), (pg_temp.u('d'), 'dana', 'Dana');

-- ---------------------------------------------------------------------
-- 2) Přepočet odznaků za noc
-- ---------------------------------------------------------------------
insert into public.nights (id, user_id, night_date, sleep_start, sleep_end, total_sleep_min, wake_count, score) values
  ('10000000-0000-0000-0000-000000000001', pg_temp.u('a'), pg_temp.today() - 1,
   ((pg_temp.today() - 2) + time '23:00') at time zone 'Europe/Prague',
   ((pg_temp.today() - 1) + time '07:00') at time zone 'Europe/Prague', 480, 2, 90);
insert into public.posts (id, kind, user_id, night_id) values
  ('20000000-0000-0000-0000-000000000001', 'night', pg_temp.u('a'), '10000000-0000-0000-0000-000000000001');
create function pg_temp.has(code text) returns boolean language sql as $$
  select exists (select 1 from public.user_achievements
                 where night_id = '10000000-0000-0000-0000-000000000001' and user_achievements.code = has.code) $$;
create function pg_temp.notif(code text) returns int language sql as $$
  select count(*)::int from public.notifications where kind = 'achievement' and payload ->> 'code' = notif.code $$;

insert into public.night_tags (night_id, tag) values ('10000000-0000-0000-0000-000000000001', 'alcohol');
select pg_temp.ok('alkohol + 90 → Navzdory', pg_temp.has('despite_it'), true);
select pg_temp.ok('Navzdory → notifikace', pg_temp.notif('despite_it'), 1);
delete from public.night_tags where night_id = '10000000-0000-0000-0000-000000000001';
select pg_temp.ok('tag smazán → Navzdory pryč', pg_temp.has('despite_it'), false);
select pg_temp.ok('tag smazán → i notifikace', pg_temp.notif('despite_it'), 0);

update public.nights set score = 96 where id = '10000000-0000-0000-0000-000000000001';
select pg_temp.ok('nová Dokonalá noc hlášená',
  public.after_night_ingest('10000000-0000-0000-0000-000000000001') -> 'new_achievements' ? 'perfect_night', true);
update public.user_achievements set earned_at = now() - interval '1 day'
where night_id = '10000000-0000-0000-0000-000000000001';
select pg_temp.ok('opakovaný ingest: nic nového',
  public.after_night_ingest('10000000-0000-0000-0000-000000000001') -> 'new_achievements', '[]'::jsonb);
select pg_temp.ok('opakovaný ingest: datum zůstalo',
  (select earned_at < now() - interval '23 hours' from public.user_achievements
   where night_id = '10000000-0000-0000-0000-000000000001' and code = 'perfect_night'), true);
select pg_temp.ok('opakovaný ingest: notifikace jen jedna', pg_temp.notif('perfect_night'), 1);
update public.nights set score = 80 where id = '10000000-0000-0000-0000-000000000001';
select public.after_night_ingest('10000000-0000-0000-0000-000000000001');
select pg_temp.ok('horší skóre → Dokonalá noc pryč', pg_temp.has('perfect_night'), false);
select pg_temp.ok('horší skóre → notifikace pryč', pg_temp.notif('perfect_night'), 0);
delete from public.notifications;
delete from public.user_achievements;
delete from public.posts;
delete from public.user_stats;
delete from public.nights;

-- ---------------------------------------------------------------------
-- 5) Milník série jen jednou: 7 dobrých nocí → streak_7; zpětně dohraná
--    starší noc posune sedmou noc o den dřív → žádný druhý odznak.
-- ---------------------------------------------------------------------
create function pg_temp.good_night(d date) returns void language sql as $$
  insert into public.nights (user_id, night_date, sleep_start, sleep_end, total_sleep_min)
  values ('00000000-0000-0000-0000-00000000000a', d,
          ((d - 1) + time '23:00') at time zone 'Europe/Prague', (d + time '07:00') at time zone 'Europe/Prague', 480) $$;
select pg_temp.good_night(pg_temp.today() - i) from generate_series(1, 7) i;
select private.recompute_streak(pg_temp.u('a'));
select pg_temp.ok('7 nocí → streak_7', (select count(*)::int from public.user_achievements where code = 'streak_7'), 1);
select pg_temp.good_night(pg_temp.today() - 8);
select private.recompute_streak(pg_temp.u('a'));
select pg_temp.ok('série 8', (select current_streak from public.user_stats where user_id = pg_temp.u('a')), 8);
select pg_temp.ok('backfill → streak_7 pořád jen jednou', (select count(*)::int from public.user_achievements where code = 'streak_7'), 1);
delete from public.notifications;
delete from public.user_achievements;
delete from public.user_stats;
delete from public.nights;

-- ---------------------------------------------------------------------
-- 3) Vzájemná bilance ve všichni proti všem
-- ---------------------------------------------------------------------
insert into public.challenges (id, type, creator_id, duration_days, start_date, end_date, status) values
  ('30000000-0000-0000-0000-000000000003', 'free_for_all', pg_temp.u('a'), 7, pg_temp.today() - 20, pg_temp.today() - 14, 'finished');
insert into public.challenge_participants (challenge_id, user_id, status, final_avg, result) values
  ('30000000-0000-0000-0000-000000000003', pg_temp.u('a'), 'accepted', 85, 'win'),
  ('30000000-0000-0000-0000-000000000003', pg_temp.u('b'), 'accepted', 80, 'loss'),
  ('30000000-0000-0000-0000-000000000003', pg_temp.u('c'), 'accepted', 70, 'loss');
select pg_temp.ok('vítěz vs poražený', (select wins::int from public.head_to_head where user_id = pg_temp.u('a') and opponent_id = pg_temp.u('c')), 1);
select pg_temp.ok('poražený vs vítěz', (select losses::int from public.head_to_head where user_id = pg_temp.u('b') and opponent_id = pg_temp.u('a')), 1);
select pg_temp.ok('poražení mezi sebou nic', (select count(*)::int from public.head_to_head where user_id = pg_temp.u('b') and opponent_id = pg_temp.u('c')), 0);
delete from public.challenges;

-- ---------------------------------------------------------------------
-- 4) Délka a vypršení
-- ---------------------------------------------------------------------
select pg_temp.err('výzva nad 30 dní neprojde',
  $$insert into public.challenges (type, creator_id, duration_days) values ('duel', '00000000-0000-0000-0000-00000000000a', 31)$$,
  'challenges_duration_max');
insert into public.challenges (id, type, creator_id, duration_days, created_at) values
  ('30000000-0000-0000-0000-000000000004', 'duel', pg_temp.u('a'), 7, now() - interval '8 days'),
  ('30000000-0000-0000-0000-000000000005', 'duel', pg_temp.u('a'), 7, now() - interval '6 days');
select pg_temp.ok('vypršela jedna', private.expire_pending_challenges(), 1);
select pg_temp.ok('stará zrušená', (select status::text from public.challenges where id = '30000000-0000-0000-0000-000000000004'), 'cancelled');
select pg_temp.ok('čerstvá čeká', (select status::text from public.challenges where id = '30000000-0000-0000-0000-000000000005'), 'pending');
delete from public.challenges;

-- ---------------------------------------------------------------------
-- 1) Kontumace: A smaže účet. S B rozjetý souboj, s C souboj od zítřka.
-- ---------------------------------------------------------------------
insert into public.challenges (id, type, creator_id, stake, duration_days, start_date, end_date, status) values
  ('30000000-0000-0000-0000-000000000001', 'duel', pg_temp.u('a'), 'pivo', 7, pg_temp.today() - 2, pg_temp.today() + 4, 'active'),
  ('30000000-0000-0000-0000-000000000002', 'duel', pg_temp.u('c'), null, 7, pg_temp.today() + 1, pg_temp.today() + 7, 'active');
insert into public.challenge_participants (challenge_id, user_id, status) values
  ('30000000-0000-0000-0000-000000000001', pg_temp.u('a'), 'accepted'),
  ('30000000-0000-0000-0000-000000000001', pg_temp.u('b'), 'accepted'),
  ('30000000-0000-0000-0000-000000000002', pg_temp.u('a'), 'accepted'),
  ('30000000-0000-0000-0000-000000000002', pg_temp.u('c'), 'accepted');
insert into public.challenge_day_scores (challenge_id, user_id, day, score) values
  ('30000000-0000-0000-0000-000000000001', pg_temp.u('a'), pg_temp.today() - 2, 90),
  ('30000000-0000-0000-0000-000000000001', pg_temp.u('b'), pg_temp.today() - 2, 70),
  ('30000000-0000-0000-0000-000000000001', pg_temp.u('b'), pg_temp.today() - 1, 80);

set role authenticated;
select set_config('request.jwt.claim.sub', pg_temp.u('a')::text, false);
select public.delete_my_account();
reset role;

select pg_temp.ok('účet pryč', (select count(*)::int from public.profiles where id = pg_temp.u('a')), 0);
select pg_temp.ok('rozjetý souboj uzavřen kontumačně',
  (select status::text || ' ' || forfeit from public.challenges where id = '30000000-0000-0000-0000-000000000001'), 'finished true');
select pg_temp.ok('soupeř vyhrál',
  (select result::text from public.challenge_participants where challenge_id = '30000000-0000-0000-0000-000000000001' and user_id = pg_temp.u('b')), 'win');
select pg_temp.ok('průměr soupeře zatím', (select final_avg from public.challenge_participants
  where challenge_id = '30000000-0000-0000-0000-000000000001' and user_id = pg_temp.u('b')), 75.00::numeric);
select pg_temp.ok('MMA soupeře', (select wins::int from public.mma_records where user_id = pg_temp.u('b')), 1);
select pg_temp.ok('pozvánka navíc', (select invites_available from public.profiles where id = pg_temp.u('b')), 4);
select pg_temp.ok('ovečka ani dluh ne',
  (select count(*)::int from public.souls) + (select count(*)::int from public.debts), 0);
select pg_temp.ok('notifikace soupeři',
  (select public.notification_text(n) from public.notifications n where n.user_id = pg_temp.u('b') and n.kind = 'challenge_result'),
  'Soupeř smazal účet. Výhra kontumačně.');
select pg_temp.ok('nezačatý souboj zrušen',
  (select status::text from public.challenges where id = '30000000-0000-0000-0000-000000000002'), 'cancelled');
select pg_temp.ok('C nic nedostane', (select invites_available from public.profiles where id = pg_temp.u('c')), 3);
