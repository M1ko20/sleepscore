-- Výzva bez soupeře (ostatní si smazali účet) se při uzávěrce zruší.
-- Spouští run.sh.
\set ON_ERROR_STOP 1

create function pg_temp.ok(msg text, got anyelement, want anyelement) returns void language plpgsql as $$
begin
  if got is distinct from want then raise exception 'FAIL: % (čekal jsem %, přišlo %)', msg, want, got; end if;
  raise notice 'ok  %', msg;
end;
$$;
create function pg_temp.u(x text) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-00000000000' || x)::uuid $$;
create function pg_temp.today() returns date language sql as $$ select (now() at time zone 'Europe/Prague')::date $$;
create function pg_temp.night(p_user uuid, p_day date, p_min int default 480) returns void language sql as $$
  insert into public.nights (user_id, night_date, sleep_start, sleep_end, total_sleep_min, score)
  values (p_user, p_day, ((p_day - 1) + time '23:00') at time zone 'Europe/Prague',
          (p_day + time '07:00') at time zone 'Europe/Prague', p_min, 80) $$;

insert into auth.users (id) values (pg_temp.u('a')), (pg_temp.u('b')), (pg_temp.u('c'));
insert into public.profiles (id, username, display_name) values
  (pg_temp.u('a'), 'adam', 'Adam'), (pg_temp.u('b'), 'bara', 'Bára'), (pg_temp.u('c'), 'cyril', 'Cyril');

-- ---------------------------------------------------------------------
-- Výzva bez soupeře
-- C1: všichni proti všem, zbyl jen B → zrušit, žádná výhra / pozvánka / odznak.
-- C2: všichni proti všem se 2 hráči → normálně.
-- C3: společný cíl s 1 hráčem → normálně (nikoho neporáží).
-- ---------------------------------------------------------------------
insert into public.challenges (id, type, creator_id, duration_days, start_date, end_date, status, stake, target_score) values
  ('30000000-0000-0000-0000-000000000001', 'free_for_all', pg_temp.u('b'), 7, pg_temp.today() - 8, pg_temp.today() - 2, 'active', 'pivo', null),
  ('30000000-0000-0000-0000-000000000002', 'free_for_all', pg_temp.u('b'), 7, pg_temp.today() - 8, pg_temp.today() - 2, 'active', 'pivo', null),
  ('30000000-0000-0000-0000-000000000003', 'team_goal',    pg_temp.u('b'), 7, pg_temp.today() - 8, pg_temp.today() - 2, 'active', null, 50);
insert into public.challenge_participants (challenge_id, user_id, status) values
  ('30000000-0000-0000-0000-000000000001', pg_temp.u('b'), 'accepted'),
  ('30000000-0000-0000-0000-000000000002', pg_temp.u('a'), 'accepted'),
  ('30000000-0000-0000-0000-000000000002', pg_temp.u('c'), 'accepted'),
  ('30000000-0000-0000-0000-000000000003', pg_temp.u('b'), 'accepted');
select pg_temp.night(pg_temp.u('a'), pg_temp.today() - 3);
update public.nights set created_at = now() - interval '5 days';   -- uložená před uzávěrkou

select pg_temp.ok('finalizace projde všemi', private.finalize_due_challenges(), 3);
select pg_temp.ok('výzva bez soupeře zrušená',
  (select status::text from public.challenges where id = '30000000-0000-0000-0000-000000000001'), 'cancelled');
select pg_temp.ok('bez výsledku',
  (select result::text from public.challenge_participants where challenge_id = '30000000-0000-0000-0000-000000000001'), null::text);
select pg_temp.ok('bez pozvánky navíc', (select invites_available from public.profiles where id = pg_temp.u('b')), 3);
select pg_temp.ok('bez odznaků', (select count(*)::int from public.user_achievements where user_id = pg_temp.u('b')
                                  and challenge_id = '30000000-0000-0000-0000-000000000001'), 0);
select pg_temp.ok('bez karty výsledku', (select count(*)::int from public.posts
                                          where challenge_id = '30000000-0000-0000-0000-000000000001'), 0);
select pg_temp.ok('dva hráči: vítěz A',
  (select result::text from public.challenge_participants
   where challenge_id = '30000000-0000-0000-0000-000000000002' and user_id = pg_temp.u('a')), 'win');
select pg_temp.ok('dva hráči: dluh C → A', (select count(*)::int from public.debts
  where challenge_id = '30000000-0000-0000-0000-000000000002' and debtor_id = pg_temp.u('c') and creditor_id = pg_temp.u('a')), 1);
select pg_temp.ok('společný cíl s jedním hráčem doběhne',
  (select status::text from public.challenges where id = '30000000-0000-0000-0000-000000000003'), 'finished');
