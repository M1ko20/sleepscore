-- Tagy v2: katalog, odznaky za otagovanou noc a Detox (7 nocí v řadě bez telefonu). Spouští run.sh.
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
-- noc i karta: id noci 1000…0NN, karty 2000…0NN
create function pg_temp.night(i int, score int, minutes int) returns uuid language plpgsql as $$
declare
  v_id uuid := ('10000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid;
begin
  insert into public.nights (id, user_id, night_date, sleep_start, sleep_end, total_sleep_min, wake_count, score)
  values (v_id, pg_temp.u('a'), pg_temp.today() - i,
          ((pg_temp.today() - i - 1) + time '23:00') at time zone 'Europe/Prague',
          ((pg_temp.today() - i - 1) + time '23:00') at time zone 'Europe/Prague' + make_interval(mins => minutes),
          minutes, 2, score);
  insert into public.posts (id, kind, user_id, night_id)
  values (('20000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid, 'night', pg_temp.u('a'), v_id);
  return v_id;
end;
$$;
create function pg_temp.n(i int) returns uuid language sql as $$
  select ('10000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid $$;
create function pg_temp.has(i int, code text) returns boolean language sql as $$
  select exists (select 1 from public.user_achievements ua where ua.night_id = pg_temp.n(i) and ua.code = has.code) $$;
create function pg_temp.cnt(code text) returns int language sql as $$
  select count(*)::int from public.user_achievements ua where ua.code = cnt.code $$;
create function pg_temp.notif(code text) returns int language sql as $$
  select count(*)::int from public.notifications where kind = 'achievement' and payload ->> 'code' = notif.code $$;

insert into auth.users (id) values (pg_temp.u('a'));
insert into public.profiles (id, username, display_name) values (pg_temp.u('a'), 'adam', 'Adam');

-- ---------------------------------------------------------------------
-- Katalog
-- ---------------------------------------------------------------------
select pg_temp.ok('kazí: alkohol, nemoc, telefon, učení',
  (select string_agg(slug, ',' order by sort) from public.tags where not positive), 'alcohol,sick,phone_in_bed,studying');
select pg_temp.ok('pomáhá: trénink, bez telefonu, čtení, sauna',
  (select string_agg(slug, ',' order by sort) from public.tags where positive), 'workout,no_phone,reading,sauna');

-- ---------------------------------------------------------------------
-- Odznaky za jednu noc
-- ---------------------------------------------------------------------
select pg_temp.night(40, 40, 480);   -- špatná noc
select pg_temp.night(41, 90, 480);   -- dobrá noc
select pg_temp.night(42, 70, 300);   -- krátká noc

insert into public.night_tags values (pg_temp.n(40), 'phone_in_bed');
select pg_temp.ok('telefon + 40 → Scroll vyhrál', pg_temp.has(40, 'scroll_won'), true);
select pg_temp.ok('Scroll vyhrál → notifikace', pg_temp.notif('scroll_won'), 1);
delete from public.night_tags where night_id = pg_temp.n(40) and tag = 'phone_in_bed';
select pg_temp.ok('tag smazán → Scroll vyhrál pryč i s notifikací', (pg_temp.has(40, 'scroll_won'), pg_temp.notif('scroll_won'))::text, '(f,0)');

insert into public.night_tags values (pg_temp.n(41), 'sick'), (pg_temp.n(41), 'workout');
select pg_temp.ok('nemoc + 90 → Nezničitelný', pg_temp.has(41, 'unbreakable'), true);
select pg_temp.ok('trénink + 90 → Regenerace', pg_temp.has(41, 'recovery'), true);
select pg_temp.ok('druhý tag nehlásí první odznak znovu', pg_temp.notif('unbreakable'), 1);
insert into public.night_tags values (pg_temp.n(40), 'sick'), (pg_temp.n(40), 'workout');
select pg_temp.ok('nemoc / trénink + 40 → nic', pg_temp.has(40, 'unbreakable') or pg_temp.has(40, 'recovery'), false);

insert into public.night_tags values (pg_temp.n(42), 'studying'), (pg_temp.n(41), 'studying');
select pg_temp.ok('učení + 5 h → Zkouškové', pg_temp.has(42, 'exam_season'), true);
select pg_temp.ok('učení + 8 h → nic', pg_temp.has(41, 'exam_season'), false);

-- ---------------------------------------------------------------------
-- Detox: každá 7. noc nepřerušené řady, tagy v libovolném pořadí
-- ---------------------------------------------------------------------
select pg_temp.night(i, 75, 450) from generate_series(1, 15) i;   -- noci 15 … 1 dní zpátky

-- 6 nocí v řadě → nic
insert into public.night_tags select pg_temp.n(i), 'no_phone' from generate_series(2, 7) i;
select pg_temp.ok('6 nocí → bez Detoxu', pg_temp.cnt('detox'), 0);

-- 7. noc doplněná zpětně (nejstarší) → Detox na nejnovější noci řady
insert into public.night_tags values (pg_temp.n(8), 'no_phone');
select pg_temp.ok('7 nocí → Detox', pg_temp.cnt('detox'), 1);
select pg_temp.ok('Detox na 7. noci řady', pg_temp.has(2, 'detox'), true);
select pg_temp.ok('Detox → notifikace', pg_temp.notif('detox'), 1);

-- 14 nocí (doplněno přeskakovaně) → 2× Detox, ten první se nehlásí znovu
insert into public.night_tags select pg_temp.n(i), 'no_phone' from generate_series(9, 15, 2) i;
insert into public.night_tags select pg_temp.n(i), 'no_phone' from generate_series(10, 14, 2) i;
select pg_temp.ok('15 nocí → 2× Detox', pg_temp.cnt('detox'), 2);
select pg_temp.ok('Detoxy na 7. a 14. noci řady', pg_temp.has(9, 'detox') and pg_temp.has(2, 'detox'), true);
select pg_temp.ok('notifikace jen 2', pg_temp.notif('detox'), 2);

-- Přerušení uprostřed → řada se rozpadne
delete from public.night_tags where night_id = pg_temp.n(8) and tag = 'no_phone';
select pg_temp.ok('díra → 1× Detox (9–15)', (pg_temp.cnt('detox'), pg_temp.has(9, 'detox'))::text, '(1,t)');
select pg_temp.ok('zrušený Detox zmizí i ze zvonečku', pg_temp.notif('detox'), 1);

