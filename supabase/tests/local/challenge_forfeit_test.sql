-- Výzva bez soupeře se vyřeší hned, když soupeř odejde (trigger na smazání účastníka).
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
create function pg_temp.ch(x text) returns uuid language sql as $$
  select ('30000000-0000-0000-0000-00000000000' || x)::uuid $$;
create function pg_temp.today() returns date language sql as $$ select (now() at time zone 'Europe/Prague')::date $$;
create function pg_temp.delete_me(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  set local role authenticated;
  perform public.delete_my_account();
  reset role;
end;
$$;
create function pg_temp.status(p_ch uuid) returns text language sql as $$
  select status::text || case when forfeit then ' forfeit' else '' end from public.challenges where id = p_ch $$;

insert into auth.users (id) select pg_temp.u(x) from unnest(array['1','2','3','4','5','6','7','8','9','a','b','c']) x;
insert into public.profiles (id, username, display_name)
select pg_temp.u(x), 'user' || x, 'User ' || x from unnest(array['1','2','3','4','5','6','7','8','9','a','b','c']) x;

-- C1: všichni proti všem 1,2,3 běží 3. den
-- C2: společný cíl jen s 4
-- C3: všichni proti všem 5,6,7 začne zítra
-- C4: čekající souboj 8 → 9 (9 ještě neodpověděl)
-- C5: rozjetý souboj a × b, b zabanovaný a pak smazaný adminem
-- C6: čekající skupinová c (zakladatel) + 1, 2 pozvaní
insert into public.challenges (id, type, creator_id, duration_days, start_date, end_date, status, stake, target_score) values
  (pg_temp.ch('1'), 'free_for_all', pg_temp.u('1'), 7, pg_temp.today() - 2, pg_temp.today() + 4, 'active', 'pivo', null),
  (pg_temp.ch('2'), 'team_goal',    pg_temp.u('4'), 7, pg_temp.today() - 2, pg_temp.today() + 4, 'active', null, 70),
  (pg_temp.ch('3'), 'free_for_all', pg_temp.u('5'), 7, pg_temp.today() + 1, pg_temp.today() + 7, 'active', null, null),
  (pg_temp.ch('4'), 'duel',         pg_temp.u('8'), 7, null, null, 'pending', null, null),
  (pg_temp.ch('5'), 'duel',         pg_temp.u('a'), 7, pg_temp.today() - 2, pg_temp.today() + 4, 'active', null, null),
  (pg_temp.ch('6'), 'free_for_all', pg_temp.u('c'), 7, null, null, 'pending', null, null);
insert into public.challenge_participants (challenge_id, user_id, status) values
  (pg_temp.ch('1'), pg_temp.u('1'), 'accepted'), (pg_temp.ch('1'), pg_temp.u('2'), 'accepted'), (pg_temp.ch('1'), pg_temp.u('3'), 'accepted'),
  (pg_temp.ch('2'), pg_temp.u('4'), 'accepted'),
  (pg_temp.ch('3'), pg_temp.u('5'), 'accepted'), (pg_temp.ch('3'), pg_temp.u('6'), 'accepted'), (pg_temp.ch('3'), pg_temp.u('7'), 'accepted'),
  (pg_temp.ch('4'), pg_temp.u('8'), 'accepted'), (pg_temp.ch('4'), pg_temp.u('9'), 'invited'),
  (pg_temp.ch('5'), pg_temp.u('a'), 'accepted'), (pg_temp.ch('5'), pg_temp.u('b'), 'accepted'),
  (pg_temp.ch('6'), pg_temp.u('c'), 'accepted'), (pg_temp.ch('6'), pg_temp.u('1'), 'invited'), (pg_temp.ch('6'), pg_temp.u('2'), 'invited');
insert into public.challenge_day_scores (challenge_id, user_id, day, score) values
  (pg_temp.ch('1'), pg_temp.u('1'), pg_temp.today() - 2, 80), (pg_temp.ch('1'), pg_temp.u('1'), pg_temp.today() - 1, 90),
  (pg_temp.ch('1'), pg_temp.u('2'), pg_temp.today() - 2, 85), (pg_temp.ch('1'), pg_temp.u('3'), pg_temp.today() - 2, 60);

-- ---------------------------------------------------------------------
-- Všichni proti všem: odejde jeden → hraje se dál; odejde poslední soupeř → kontumace
-- ---------------------------------------------------------------------
select pg_temp.delete_me(pg_temp.u('2'));
select pg_temp.ok('po odchodu jednoho běží dál', pg_temp.status(pg_temp.ch('1')), 'active');
delete from auth.users where id = pg_temp.u('3');            -- ruční smazání adminem
select pg_temp.ok('poslední soupeř pryč → kontumace', pg_temp.status(pg_temp.ch('1')), 'finished forfeit');
select pg_temp.ok('zbylý vyhrál', (select result::text || ' ' || final_avg from public.challenge_participants
  where challenge_id = pg_temp.ch('1') and user_id = pg_temp.u('1')), 'win 85.00');
select pg_temp.ok('pozvánka navíc', (select invites_available from public.profiles where id = pg_temp.u('1')), 4);
select pg_temp.ok('MMA výhra', (select wins::int from public.mma_records where user_id = pg_temp.u('1')), 1);
select pg_temp.ok('jedna notifikace s textem',
  (select string_agg(public.notification_text(n), '|') from public.notifications n
   where n.user_id = pg_temp.u('1') and n.kind = 'challenge_result'),
  'Ostatní smazali účet. Výhra kontumačně.');
select pg_temp.ok('ani dluh, ani ovečka',
  (select count(*)::int from public.debts where challenge_id = pg_temp.ch('1'))
  + (select count(*)::int from public.souls where winner_id = pg_temp.u('1')), 0);
select pg_temp.ok('uzávěrka ji už nezpracuje', private.finalize_due_challenges(), 0);

-- ---------------------------------------------------------------------
-- Společný cíl bez lidí, nezačatá výzva, čekající souboj, čekající skupina
-- ---------------------------------------------------------------------
select pg_temp.delete_me(pg_temp.u('4'));
select pg_temp.ok('prázdný společný cíl zrušen', pg_temp.status(pg_temp.ch('2')), 'cancelled');
select pg_temp.ok('bez karty výsledku', (select count(*)::int from public.posts where challenge_id = pg_temp.ch('2')), 0);

select pg_temp.delete_me(pg_temp.u('6'));
select pg_temp.delete_me(pg_temp.u('7'));
select pg_temp.ok('nezačatá výzva bez soupeřů zrušena', pg_temp.status(pg_temp.ch('3')), 'cancelled');
select pg_temp.ok('nezačatá: žádná pozvánka', (select invites_available from public.profiles where id = pg_temp.u('5')), 3);
select pg_temp.ok('nezačatá: notifikace o zrušení',
  (select public.notification_text(n) from public.notifications n
   where n.user_id = pg_temp.u('5') and n.challenge_id = pg_temp.ch('3')),
  'Ostatní smazali účet. Výzva se ruší.');

select pg_temp.delete_me(pg_temp.u('9'));
select pg_temp.ok('čekající souboj bez pozvaného zrušen', pg_temp.status(pg_temp.ch('4')), 'cancelled');
select pg_temp.ok('čekající souboj: notifikace zakladateli',
  (select public.notification_text(n) from public.notifications n
   where n.user_id = pg_temp.u('8') and n.challenge_id = pg_temp.ch('4')),
  'Soupeř smazal účet. Souboj se ruší.');

-- u('1') a u('2') už jsou smazaní výš → v C6 zbyl jen zakladatel, výzva dál čeká
select pg_temp.ok('čekající skupina čeká dál', pg_temp.status(pg_temp.ch('6')), 'pending');

-- ---------------------------------------------------------------------
-- Ban a pak ruční smazání: soupeř vyhraje kontumačně, výzva se nezruší
-- ---------------------------------------------------------------------
select private.ban_user(pg_temp.u('b'), 'test');
select pg_temp.ok('ban: souboj běží', pg_temp.status(pg_temp.ch('5')), 'active');
delete from auth.users where id = pg_temp.u('b');
select pg_temp.ok('smazání po banu: kontumace', pg_temp.status(pg_temp.ch('5')), 'finished forfeit');
select pg_temp.ok('soupeř vyhrál', (select result::text from public.challenge_participants
  where challenge_id = pg_temp.ch('5') and user_id = pg_temp.u('a')), 'win');
select pg_temp.ok('text pro souboj',
  (select public.notification_text(n) from public.notifications n
   where n.user_id = pg_temp.u('a') and n.kind = 'challenge_result'),
  'Soupeř smazal účet. Výhra kontumačně.');

-- ---------------------------------------------------------------------
-- Rozjetý souboj přes delete_my_account dál kontumací (pravidlo #37)
-- ---------------------------------------------------------------------
insert into public.challenges (id, type, creator_id, duration_days, start_date, end_date, status) values
  (pg_temp.ch('7'), 'duel', pg_temp.u('5'), 7, pg_temp.today() - 1, pg_temp.today() + 5, 'active');
insert into public.challenge_participants (challenge_id, user_id, status) values
  (pg_temp.ch('7'), pg_temp.u('5'), 'accepted'), (pg_temp.ch('7'), pg_temp.u('8'), 'accepted');
select pg_temp.delete_me(pg_temp.u('8'));
select pg_temp.ok('souboj: kontumace', pg_temp.status(pg_temp.ch('7')), 'finished forfeit');
select pg_temp.ok('souboj: pozvánka', (select invites_available from public.profiles where id = pg_temp.u('5')), 4);
