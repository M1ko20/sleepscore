-- Opravy z code review: neplatné pásmo (#33), freeze při nulové sérii (#34),
-- uzávěrka výzvy (#35), drobnosti (#36). Spouští run.sh.
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

insert into auth.users (id) values (pg_temp.u('a')), (pg_temp.u('b'));
insert into public.profiles (id, username, display_name) values
  (pg_temp.u('a'), 'adam', 'Adam'), (pg_temp.u('b'), 'bara', 'Bára');

-- ---------------------------------------------------------------------
-- #33 časové pásmo
-- ---------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.sub', pg_temp.u('a')::text, false);
select pg_temp.err('klient pásmo přímo nezmění',
  $$update public.profiles set timezone = 'Mars/Olympus' where id = '00000000-0000-0000-0000-00000000000a'$$,
  'permission denied');
reset role;

select pg_temp.err('neplatné pásmo odmítnuto i serveru',
  $$update public.profiles set timezone = 'Mars/Olympus' where id = '00000000-0000-0000-0000-00000000000a'$$,
  'invalid timezone');
update public.profiles set timezone = 'America/New_York' where id = pg_temp.u('b');
select pg_temp.ok('platné pásmo projde', (select timezone from public.profiles where id = pg_temp.u('b')), 'America/New_York');
update public.profiles set timezone = 'Europe/Prague' where id = pg_temp.u('b');

insert into public.challenges (id, type, creator_id, duration_days, timezone)
values ('30000000-0000-0000-0000-000000000009', 'duel', pg_temp.u('a'), 7, 'Bad/Zone');
select pg_temp.ok('výzva s neplatným pásmem → Praha',
  (select timezone from public.challenges where id = '30000000-0000-0000-0000-000000000009'), 'Europe/Prague');
delete from public.challenges where id = '30000000-0000-0000-0000-000000000009';

select private.hourly_jobs();
select private.notification_jobs();
select pg_temp.ok('hodinové úlohy proběhnou', true, true);

-- ---------------------------------------------------------------------
-- #34 freeze jen když běží série
-- Po špatná, Út–Čt dobré, Pá špatná (freeze), So–Ne dobré → 5
-- ---------------------------------------------------------------------
do $$
declare d date := date_trunc('week', current_date)::date - 14; i int;
begin
  for i in 0..6 loop
    insert into public.nights (user_id, night_date, sleep_start, sleep_end, total_sleep_min)
    values ('00000000-0000-0000-0000-00000000000a', d + i,
            ((d + i - 1) + time '23:00') at time zone 'Europe/Prague',
            ((d + i) + time '07:00') at time zone 'Europe/Prague',
            case when i in (0, 4) then 200 else 480 end);
  end loop;
end $$;
select private.recompute_streak(pg_temp.u('a'));
select pg_temp.ok('freeze nespotřebovaný při nulové sérii', (select best_streak from public.user_stats where user_id = pg_temp.u('a')), 5);
delete from public.nights;
delete from public.user_stats;

-- ---------------------------------------------------------------------
-- #35 uzávěrka výzvy
-- C1: skončila včera ve 14:00 (ještě nefinalizovaná), C2: běží.
-- ---------------------------------------------------------------------
create function pg_temp.today() returns date language sql as $$ select (now() at time zone 'Europe/Prague')::date $$;
insert into public.challenges (id, type, creator_id, duration_days, start_date, end_date, status) values
  ('30000000-0000-0000-0000-000000000001', 'duel', pg_temp.u('a'), 7, pg_temp.today() - 7, pg_temp.today() - 1, 'active'),
  ('30000000-0000-0000-0000-000000000002', 'duel', pg_temp.u('a'), 7, pg_temp.today() - 3, pg_temp.today() + 3, 'active');
insert into public.challenge_participants (challenge_id, user_id, status)
select c, u, 'accepted' from unnest(array['30000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002']::uuid[]) c,
  unnest(array[pg_temp.u('a'), pg_temp.u('b')]) u;

-- A: poslední noc uložená před uzávěrkou (ale do výzvy se nepropsala),
-- B: poslední noc nahraná až po uzávěrce.
insert into public.nights (id, user_id, night_date, sleep_start, sleep_end, total_sleep_min, score, created_at) values
  ('10000000-0000-0000-0000-00000000000a', pg_temp.u('a'), pg_temp.today() - 1,
   now() - interval '32 hours', now() - interval '24 hours', 480, 70, ((pg_temp.today() - 1) + time '13:00') at time zone 'Europe/Prague'),
  ('10000000-0000-0000-0000-00000000000b', pg_temp.u('b'), pg_temp.today() - 1,
   now() - interval '32 hours', now() - interval '24 hours', 480, 99, now());

insert into public.challenge_day_scores (challenge_id, user_id, day, score, night_id) values
  ('30000000-0000-0000-0000-000000000001', pg_temp.u('b'), pg_temp.today() - 1, 99, '10000000-0000-0000-0000-00000000000b');
select pg_temp.ok('po uzávěrce se denní skóre nezapíše',
  (select count(*)::int from public.challenge_day_scores where challenge_id = '30000000-0000-0000-0000-000000000001'), 0);

insert into public.challenge_day_scores (challenge_id, user_id, day, score, night_id) values
  ('30000000-0000-0000-0000-000000000002', pg_temp.u('b'), pg_temp.today() - 1, 99, '10000000-0000-0000-0000-00000000000b');
select pg_temp.ok('do běžící výzvy se zapíše',
  (select count(*)::int from public.challenge_day_scores where challenge_id = '30000000-0000-0000-0000-000000000002'), 1);

select pg_temp.ok('finalizace proběhne', private.finalize_due_challenges(), 1);
select pg_temp.ok('noc před uzávěrkou se započítá',
  (select score::int from public.challenge_day_scores
   where challenge_id = '30000000-0000-0000-0000-000000000001' and user_id = pg_temp.u('a') and day = pg_temp.today() - 1), 70);
select pg_temp.ok('noc po uzávěrce = 0',
  (select score::int from public.challenge_day_scores
   where challenge_id = '30000000-0000-0000-0000-000000000001' and user_id = pg_temp.u('b') and day = pg_temp.today() - 1), 0);
select pg_temp.ok('všech 7 dní obou hráčů',
  (select count(*)::int from public.challenge_day_scores where challenge_id = '30000000-0000-0000-0000-000000000001'), 14);

update public.challenge_day_scores set score = 100
where challenge_id = '30000000-0000-0000-0000-000000000001' and user_id = pg_temp.u('b');
select pg_temp.ok('uzavřená výzva se nemění',
  (select max(score)::int from public.challenge_day_scores
   where challenge_id = '30000000-0000-0000-0000-000000000001' and user_id = pg_temp.u('b')), 0);

-- ---------------------------------------------------------------------
-- #36
-- ---------------------------------------------------------------------
select pg_temp.ok('minutes_since_noon je stable',
  (select provolatile::text from pg_proc where proname = 'minutes_since_noon'), 's');
