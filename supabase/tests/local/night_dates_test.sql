-- Noci podle data noci: feed_night_posts řadí podle night_date (ne podle importu),
-- user_night_posts vrací noci jednoho uživatele za rozsah dní jen přátelům. Spouští run.sh.
\set ON_ERROR_STOP 1

create function public.t_ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAIL: %', msg; end if;
  raise notice 'ok  %', msg;
end;
$$;
grant execute on function public.t_ok(boolean, text) to authenticated;

create function public.u(x text) returns uuid language sql immutable as $$
  select ('00000000-0000-0000-0000-0000000000' || x)::uuid;
$$;
create function public.t_as(p_user text) returns text language sql as $$
  select set_config('request.jwt.claim.sub', public.u(p_user)::text, false);
$$;
grant execute on function public.u(text), public.t_as(text) to authenticated;

-- A–B přátelé, C cizí.
insert into auth.users (id) select public.u(x) from unnest(array['0a', '0b', '0c']) x;
insert into public.profiles (id, username, display_name)
select public.u(x), 'user' || x, 'User ' || x from unnest(array['0a', '0b', '0c']) x;
insert into public.friendships (user_a, user_b, requested_by, status)
values (least(public.u('0a'), public.u('0b')), greatest(public.u('0a'), public.u('0b')), public.u('0a'), 'accepted');

-- B: noc včera nahraná včera ráno, noc dnes nahraná dnes ráno.
-- A: tři staré noci (před 5–7 dny) nahrané až teď (první synchronizace).
insert into public.nights (user_id, night_date, sleep_start, sleep_end, total_sleep_min, score)
select public.u(x), current_date - g, (current_date - g) + time '06:30' - interval '8 hours',
       (current_date - g) + time '06:30', 470, 80
from (values ('0b', 0), ('0b', 1), ('0a', 5), ('0a', 6), ('0a', 7), ('0c', 0), ('0c', 40)) v(x, g);
insert into public.posts (kind, user_id, night_id, created_at)
select 'night', n.user_id, n.id,
       case when n.user_id = public.u('0a') then now() else n.sleep_end end
from public.nights n;

set role authenticated;

-- =====================================================================
-- Feed podle data noci
-- =====================================================================
select t_as('0a');
select t_ok(array(select n.night_date from public.feed_night_posts(30) p join public.nights n on n.id = p.night_id)
            = array[current_date, current_date - 1, current_date - 5, current_date - 6, current_date - 7],
            'A: zpětně nahrané staré noci nejsou nahoře, pořadí podle data noci');
select t_ok((select count(*) from public.feed_night_posts(30)) = 5, 'A: nic od C');
select t_ok((select count(*) from public.feed_night_posts(2)) = 2, 'limit platí');

-- =====================================================================
-- Noci v profilu
-- =====================================================================
select t_ok(array(select n.night_date from public.user_night_posts(u('0a'), current_date - 30, current_date) p
                  join public.nights n on n.id = p.night_id)
            = array[current_date - 5, current_date - 6, current_date - 7], 'A: moje noci od nejnovější');
select t_ok((select count(*) from public.user_night_posts(u('0b'), current_date - 30, current_date)) = 2, 'A: noci přítele B');
select t_ok((select count(*) from public.user_night_posts(u('0b'), current_date, current_date)) = 1, 'rozsah včetně krajů');
select t_ok((select count(*) from public.user_night_posts(u('0c'), current_date - 60, current_date)) = 0, 'A: noci cizího C nevidí');
select t_as('0c');
select t_ok((select count(*) from public.user_night_posts(u('0c'), current_date - 60, current_date)) = 2, 'C: svoje noci vidí');
select t_ok((select count(*) from public.user_night_posts(u('0c'), current_date - 30, current_date)) = 1, 'C: starší noc mimo rozsah');

-- nahlášená karta zmizí i z profilu
select t_as('0b');
select public.report_content('post', (select p.id from public.posts p join public.nights n on n.id = p.night_id
                                      where p.user_id = u('0a') and n.night_date = current_date - 5), 'spam');
select t_ok((select count(*) from public.user_night_posts(u('0a'), current_date - 30, current_date)) = 2,
            'B: nahlášenou noc A v profilu nevidí');

reset role;
set role anon;
do $$ begin
  perform public.user_night_posts(public.u('0a'), current_date - 30, current_date);
  raise exception 'FAIL: anon spustil user_night_posts';
exception when insufficient_privilege then raise notice 'ok  anon nemá user_night_posts';
end $$;
reset role;
