-- Nastavení notifikací (#11): výchozí stav, uložení, validace, RLS, rozhodnutí pro push, export.
-- Spouští run.sh.
\set ON_ERROR_STOP 1

create function public.t_ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAIL: %', msg; end if;
  raise notice 'ok  %', msg;
end;
$$;
-- Očekávaná chyba: spustí SQL a ověří, že selže se zprávou obsahující p_expect.
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

-- A v Praze, B v New Yorku, C s rozbitým časovým pásmem.
insert into auth.users (id) values
  ('00000000-0000-0000-0000-00000000000a'),
  ('00000000-0000-0000-0000-00000000000b'),
  ('00000000-0000-0000-0000-00000000000c');
-- C: neplatné pásmo (od #33 ho trigger nepustí – simulujeme stará data, fallback zůstává)
alter table public.profiles disable trigger profiles_guard_timezone;
insert into public.profiles (id, username, display_name, timezone) values
  ('00000000-0000-0000-0000-00000000000a', 'adam', 'Adam', 'Europe/Prague'),
  ('00000000-0000-0000-0000-00000000000b', 'jakub', 'Jakub', 'America/New_York'),
  ('00000000-0000-0000-0000-00000000000c', 'karolina', 'Karolína', 'Mars/Olympus');
alter table public.profiles enable trigger profiles_guard_timezone;

-- ---------------------------------------------------------------------
-- A: výchozí stav, uložení, validace
-- ---------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);

select t_ok(public.my_notification_prefs() = '{"reactions": true, "comments": true, "friends": true, "challenges": true,
  "achievements": true, "morning": true, "recap": true, "quiet_hours": true}'::jsonb, 'výchozí: vše zapnuto, noční klid zapnutý');
select t_ok(not exists (select 1 from public.notification_prefs), 'výchozí stav nic neukládá');

select t_ok(public.set_notification_prefs('{"reactions": false}') ->> 'reactions' = 'false', 'vypnout reakce');
select t_ok((public.my_notification_prefs() ->> 'comments')::boolean, 'ostatní zůstanou zapnuté');
select t_ok(public.set_notification_prefs('{"quiet_hours": false, "recap": false}') = '{"reactions": false, "comments": true,
  "friends": true, "challenges": true, "achievements": true, "morning": true, "recap": false, "quiet_hours": false}'::jsonb,
  'druhá změna se sloučí s první');
select t_ok(public.set_notification_prefs('{}') ->> 'reactions' = 'false', 'prázdná změna nic nemění');

select t_err($$select public.set_notification_prefs('{"likes": false}')$$, 'invalid notification prefs', 'neznámý klíč');
select t_err($$select public.set_notification_prefs('{"reactions": "no"}')$$, 'invalid notification prefs', 'hodnota není boolean');
select t_err($$select public.set_notification_prefs('{"reactions": null}')$$, 'invalid notification prefs', 'null místo boolean');
select t_err($$select public.set_notification_prefs('[true]')$$, 'invalid notification prefs', 'pole místo objektu');
select t_err($$select public.set_notification_prefs(null)$$, 'invalid notification prefs', 'null');

-- přímý zápis z klienta nejde
select t_err($$update public.notification_prefs set prefs = prefs || '{"reactions": true}'$$, 'permission denied', 'klient nemůže update');
select t_err($$insert into public.notification_prefs (user_id) values ('00000000-0000-0000-0000-00000000000b')$$,
  'permission denied', 'klient nemůže insert');
select t_err($$delete from public.notification_prefs$$, 'permission denied', 'klient nemůže delete');
-- helper pro push je jen pro server
select t_err($$select private.push_decision('00000000-0000-0000-0000-00000000000a'::uuid, 'comments')$$,
  'permission denied', 'klient nevolá push_decision');

-- export obsahuje nastavení
select t_ok(public.export_my_data() -> 'notification_prefs' ->> 'reactions' = 'false', 'export: nastavení');
select t_ok(public.export_my_data() -> 'notification_prefs' ->> 'updated_at' is not null, 'export: čas změny');
reset role;

-- B vidí jen svoje
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select t_ok((select count(*) from public.notification_prefs) = 0, 'cizí nastavení přes RLS nevidím');
select t_ok((public.my_notification_prefs() ->> 'reactions')::boolean, 'B má svoje výchozí');
select t_ok(public.export_my_data() -> 'notification_prefs' ->> 'quiet_hours' = 'true', 'export bez uloženého řádku = výchozí');
select t_ok(public.export_my_data() -> 'notification_prefs' -> 'updated_at' = 'null'::jsonb, 'export bez řádku: updated_at null');
reset role;

-- nepřihlášený / zabanovaný
set role authenticated;
select set_config('request.jwt.claim.sub', '', false);
select t_err($$select public.set_notification_prefs('{"reactions": false}')$$, 'not a member', 'bez přihlášení nejde uložit');
reset role;
update public.profiles set banned_at = now() where id = '00000000-0000-0000-0000-00000000000c';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
select t_err($$select public.set_notification_prefs('{"reactions": false}')$$, 'not a member', 'zabanovaný nejde uložit');
reset role;
update public.profiles set banned_at = null where id = '00000000-0000-0000-0000-00000000000c';

-- anon nic
set role anon;
select t_err($$select public.my_notification_prefs()$$, 'permission denied', 'anon nečte');
select t_err($$select public.set_notification_prefs('{}')$$, 'permission denied', 'anon nezapisuje');
reset role;

-- check v DB drží i proti service role
select t_err($$insert into public.notification_prefs (user_id, prefs) values ('00000000-0000-0000-0000-00000000000b', '{"reactions": true}')$$,
  'notification_prefs_valid', 'uložené musí být úplné');
select t_err($$update public.notification_prefs set prefs = prefs || '{"x": true}'$$, 'notification_prefs_valid', 'neznámý klíč ani přes server');

-- ---------------------------------------------------------------------
-- Rozhodnutí pro push (#10). 7. 11. 2026: Praha = UTC+1, New York = UTC-5.
-- A: reakce a recap vypnuté, noční klid vypnutý.
-- ---------------------------------------------------------------------
select t_ok(private.push_decision('00000000-0000-0000-0000-00000000000a'::uuid, 'reactions', '2026-11-07 12:00+00') = 'skip', 'A: vypnutá kategorie = skip');
select t_ok(private.push_decision('00000000-0000-0000-0000-00000000000a'::uuid, 'comments', '2026-11-07 23:30+00') = 'send', 'A: bez nočního klidu i v noci send');
select t_ok(private.push_decision('00000000-0000-0000-0000-00000000000a'::uuid, 'reactions', '2026-11-07 23:30+00') = 'skip', 'A: vypnutá kategorie v noci = skip');

-- B: výchozí (noční klid 22–8 New York)
select t_ok(private.push_decision('00000000-0000-0000-0000-00000000000b'::uuid, 'comments', '2026-11-07 20:59+00') = 'send', 'B: 15:59 NY send');
select t_ok(private.push_decision('00000000-0000-0000-0000-00000000000b'::uuid, 'comments', '2026-11-07 22:30+00') = 'send', 'B: 17:30 NY send (v Praze už noc)');
select t_ok(private.push_decision('00000000-0000-0000-0000-00000000000b'::uuid, 'comments', '2026-11-08 03:00+00') = 'hold', 'B: 22:00 NY hold');
select t_ok(private.push_decision('00000000-0000-0000-0000-00000000000b'::uuid, 'comments', '2026-11-08 12:59+00') = 'hold', 'B: 7:59 NY hold');
select t_ok(private.push_decision('00000000-0000-0000-0000-00000000000b'::uuid, 'comments', '2026-11-08 13:00+00') = 'send', 'B: 8:00 NY send');
select t_ok(private.push_decision('00000000-0000-0000-0000-00000000000b'::uuid, 'unknown', '2026-11-08 13:00+00') = 'send', 'neznámá kategorie = zapnutá');

-- C: rozbité pásmo → Praha
select t_ok(private.push_decision('00000000-0000-0000-0000-00000000000c'::uuid, 'comments', '2026-11-07 21:30+00') = 'hold', 'C: neplatné pásmo → Praha 22:30 hold');
select t_ok(private.push_decision('00000000-0000-0000-0000-00000000000c'::uuid, 'comments', '2026-11-07 20:30+00') = 'send', 'C: Praha 21:30 send');

-- neexistující uživatel
select t_ok(private.push_decision('00000000-0000-0000-0000-0000000000ff'::uuid, 'comments') = 'skip', 'neexistující uživatel = skip');

-- varianta pro řádek z fronty (category z notifikace)
insert into public.notifications (user_id, kind, actor_id) values
  ('00000000-0000-0000-0000-00000000000a', 'reaction', '00000000-0000-0000-0000-00000000000b'),
  ('00000000-0000-0000-0000-00000000000a', 'friend_request', '00000000-0000-0000-0000-00000000000b'),
  ('00000000-0000-0000-0000-00000000000b', 'weekly_recap', null);
select t_ok((select private.push_decision(n, '2026-11-07 12:00+00') from public.notifications n
             where n.kind = 'reaction') = 'skip', 'řádek: reakce A = skip');
select t_ok((select private.push_decision(n, '2026-11-07 12:00+00') from public.notifications n
             where n.kind = 'friend_request') = 'send', 'řádek: žádost A = send');
select t_ok((select private.push_decision(n, '2026-11-08 05:00+00') from public.notifications n
             where n.kind = 'weekly_recap') = 'hold', 'řádek: recap B v noci = hold');

-- zvoneček dál ukazuje vše (filtr je jen pro push)
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select t_ok((select count(*) from public.notifications) = 2, 'zvoneček: A vidí i vypnuté reakce');
reset role;

-- smazání profilu smaže nastavení
delete from public.profiles where id = '00000000-0000-0000-0000-00000000000a';
select t_ok(not exists (select 1 from public.notification_prefs), 'smazaný účet = smazané nastavení');
