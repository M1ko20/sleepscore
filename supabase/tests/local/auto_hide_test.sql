-- Moderace #15: automatické skrytí po 3 hlášeních od různých lidí. Spouští run.sh.
\set ON_ERROR_STOP 1

create function public.t_ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAIL: %', msg; end if;
  raise notice 'ok  %', msg;
end;
$$;
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

-- Přepnutí uživatele: t_as('0b') = 00000000-0000-0000-0000-00000000000b
create function public.t_as(p_user text) returns text language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || p_user, false);
$$;
grant execute on function public.t_as(text) to authenticated;

-- B je autor. A, C, D, E, F jsou přátelé B; A je přítel všech.
insert into auth.users (id) select ('00000000-0000-0000-0000-0000000000' || x)::uuid
from unnest(array['0a', '0b', '0c', '0d', '0e', '0f']) x;
insert into public.profiles (id, username, display_name, avatar_path) values
  ('00000000-0000-0000-0000-00000000000a', 'adam', 'Adam', null),
  ('00000000-0000-0000-0000-00000000000b', 'jakub', 'Jakub Hrubý', '00000000-0000-0000-0000-00000000000b/a.jpg'),
  ('00000000-0000-0000-0000-00000000000c', 'karolina', 'Karolína', null),
  ('00000000-0000-0000-0000-00000000000d', 'david', 'David', null),
  ('00000000-0000-0000-0000-00000000000e', 'eva', 'Eva', null),
  ('00000000-0000-0000-0000-00000000000f', 'filip', 'Filip', null);
insert into public.friendships (user_a, user_b, requested_by, status)
select least(x, y), greatest(x, y), x, 'accepted'
from (values ('00000000-0000-0000-0000-00000000000b'::uuid), ('00000000-0000-0000-0000-00000000000a'::uuid)) a(x),
     (select ('00000000-0000-0000-0000-0000000000' || z)::uuid from unnest(array['0a', '0c', '0d', '0e', '0f']) z) b(y)
where x <> y
on conflict do nothing;
insert into public.nights (id, user_id, night_date, sleep_start, sleep_end, total_sleep_min, score) values
  ('10000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000000b', current_date,
   now() - interval '8 hours', now(), 470, 80),
  ('10000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-00000000000b', current_date - 1,
   now() - interval '32 hours', now() - interval '24 hours', 470, 80),
  ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000a', current_date,
   now() - interval '8 hours', now(), 470, 80);
insert into public.posts (id, kind, user_id, night_id, title, photo_path) values
  ('20000000-0000-0000-0000-0000000000b1', 'night', '00000000-0000-0000-0000-00000000000b',
   '10000000-0000-0000-0000-0000000000b1', 'urážka', '00000000-0000-0000-0000-00000000000b/x.jpg'),
  ('20000000-0000-0000-0000-0000000000b2', 'night', '00000000-0000-0000-0000-00000000000b',
   '10000000-0000-0000-0000-0000000000b2', 'druhá urážka', null),
  ('20000000-0000-0000-0000-0000000000a1', 'night', '00000000-0000-0000-0000-00000000000a',
   '10000000-0000-0000-0000-0000000000a1', 'Adamova noc', null);
insert into public.comments (id, post_id, user_id, body) values
  ('30000000-0000-0000-0000-0000000000b1', '20000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000b', 'sprostý komentář'),
  ('30000000-0000-0000-0000-0000000000c1', '20000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000000c', 'Karolína u Jakuba');
insert into public.challenges (id, type, creator_id, duration_days, status, stake) values
  ('40000000-0000-0000-0000-000000000001', 'duel', '00000000-0000-0000-0000-00000000000b', 7, 'active', 'sprostá sázka');
insert into public.challenge_participants (challenge_id, user_id, status) values
  ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'accepted'),
  ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'accepted');
insert into private.app_config values ('report_webhook_url', 'https://ntfy.sh/tajne-tema'),
                                      ('report_webhook_format', 'ntfy');

-- =====================================================================
-- Karta: E nahlásí a pak je zabanovaná, A a C nahlásí → zatím 2 platná
-- =====================================================================
set role authenticated;
select t_as('0e'); select public.report_content('post', '20000000-0000-0000-0000-0000000000b1', 'spam');
reset role;
update public.profiles set banned_at = now() where id = '00000000-0000-0000-0000-00000000000e';
set role authenticated;
select t_as('0a'); select public.report_content('post', '20000000-0000-0000-0000-0000000000b1', 'harassment');
select t_as('0c'); select public.report_content('post', '20000000-0000-0000-0000-0000000000b1', 'harassment');
select public.report_content('post', '20000000-0000-0000-0000-0000000000b1', 'spam');  -- opakované = nic nového
select t_as('0f');
select t_ok((select count(*) from public.posts where id = '20000000-0000-0000-0000-0000000000b1') = 1,
            '2 platná hlášení (+ zabanovaný, + opakované): karta vidět');
select t_as('0d'); select public.report_content('post', '20000000-0000-0000-0000-0000000000b1', 'hate');
select t_as('0f');
select t_ok((select count(*) from public.posts where id = '20000000-0000-0000-0000-0000000000b1') = 0,
            '3. hlášení: karta skrytá i pro nehlásícího');
select t_ok((select count(*) from public.comments where id = '30000000-0000-0000-0000-0000000000c1') = 0,
            'komentáře skryté karty nejsou vidět');
select t_err($$insert into public.comments (post_id, user_id, body) values ('20000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000000f', 'x')$$,
             'row-level security', 'skrytou kartu nejde komentovat');
select t_err($$insert into public.reactions (post_id, user_id, kind) values ('20000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000000f', 'beer')$$,
             'row-level security', 'na skrytou kartu nejde reagovat');
select t_err($$select public.report_content('post', '20000000-0000-0000-0000-0000000000b1', 'spam')$$,
             'content not found', 'skrytou kartu už nejde nahlásit');
select t_ok((select count(*) from public.posts where id = '20000000-0000-0000-0000-0000000000a1') = 1, 'ostatní karty beze změny');
select t_as('0b');
select t_ok((select hidden_at is not null from public.posts where id = '20000000-0000-0000-0000-0000000000b1'),
            'autor kartu vidí i s hidden_at');
select t_ok((select count(*) from public.comments where id = '30000000-0000-0000-0000-0000000000c1') = 1,
            'autor vidí komentáře pod svou skrytou kartou');
reset role;
select t_ok((select count(*) from net.requests where body ->> 'title' = 'Obsah automaticky skrytý po 3 hlášeních') = 1,
            'upozornění: automaticky skryto (jednou)');
select t_ok((select body ->> 'message' from net.requests where body ->> 'title' like 'Obsah automaticky%') not like '%urážka%'
            and (select body ->> 'message' from net.requests where body ->> 'title' like 'Obsah automaticky%') not like '%akub%',
            'upozornění bez obsahu a jmen');

-- dismiss → zase vidět všem
select private.resolve_report((select id from public.reports where target_id = '20000000-0000-0000-0000-0000000000b1' limit 1), 'dismiss');
select t_ok((select hidden_at is null from public.posts where id = '20000000-0000-0000-0000-0000000000b1'), 'dismiss: hidden_at null');
select t_ok((select count(*) from public.reports where target_id = '20000000-0000-0000-0000-0000000000b1' and status = 'open') = 0,
            'dismiss: všechna hlášení vyřízená');
set role authenticated;
select t_as('0f');
select t_ok((select count(*) from public.posts where id = '20000000-0000-0000-0000-0000000000b1') = 1, 'po dismiss karta zase vidět');
select t_as('0a');
select t_ok((select count(*) from public.posts where id = '20000000-0000-0000-0000-0000000000b1') = 0, 'hlásícímu zůstává skrytá');
reset role;
select t_ok(not exists (select 1 from private.hidden_content), 'dismiss: záznam o skrytí pryč');

-- =====================================================================
-- Komentář Jakuba u Adamovy karty → skrytý, pak dismiss
-- =====================================================================
select t_ok((select payload ? 'text' from public.notifications where comment_id = '30000000-0000-0000-0000-0000000000b1'),
            'notifikace komentáře má text');
set role authenticated;
select t_as('0c'); select public.report_content('comment', '30000000-0000-0000-0000-0000000000b1', 'hate');
select t_as('0d'); select public.report_content('comment', '30000000-0000-0000-0000-0000000000b1', 'hate');
select t_as('0f'); select public.report_content('comment', '30000000-0000-0000-0000-0000000000b1', 'hate');
select t_as('0a');
select t_ok((select count(*) from public.comments where id = '30000000-0000-0000-0000-0000000000b1') = 0,
            'skrytý komentář nevidí ani majitel karty');
select t_ok(not (select payload ? 'text' from public.notifications where comment_id = '30000000-0000-0000-0000-0000000000b1'),
            'text komentáře zmizel z notifikace');
select t_as('0b');
select t_ok((select hidden_at is not null from public.comments where id = '30000000-0000-0000-0000-0000000000b1'),
            'autor svůj skrytý komentář vidí s hidden_at');
reset role;
select private.resolve_report((select id from public.reports where target_id = '30000000-0000-0000-0000-0000000000b1' limit 1), 'dismiss');
set role authenticated;
select t_as('0a');
select t_ok((select count(*) from public.comments where id = '30000000-0000-0000-0000-0000000000b1') = 1, 'po dismiss komentář zase vidět');
select t_ok((select payload ->> 'text' from public.notifications where comment_id = '30000000-0000-0000-0000-0000000000b1') = 'sprostý komentář',
            'po dismiss text v notifikaci zpět');
reset role;

-- =====================================================================
-- Profil: jen jméno a profilovka, změna zamčená, dismiss vrátí
-- =====================================================================
set role authenticated;
select t_as('0a'); select public.report_content('profile', '00000000-0000-0000-0000-00000000000b', 'sexual');
select t_as('0c'); select public.report_content('profile', '00000000-0000-0000-0000-00000000000b', 'sexual');
select t_as('0d'); select public.report_content('profile', '00000000-0000-0000-0000-00000000000b', 'sexual');
select t_as('0f');
select t_ok((select display_name = 'jakub' and avatar_path is null from public.profiles
             where id = '00000000-0000-0000-0000-00000000000b'), 'profil: jméno = přezdívka, bez fotky');
select t_ok((select count(*) from public.posts where user_id = '00000000-0000-0000-0000-00000000000b') = 2, 'profil: karty dál vidět');
select t_as('0b');
select t_err($$update public.profiles set display_name = 'Zase sprostě' where id = '00000000-0000-0000-0000-00000000000b'$$,
             'profile hidden pending review', 'skryté jméno nejde změnit');
select t_err($$update public.profiles set avatar_path = '00000000-0000-0000-0000-00000000000b/b.jpg' where id = '00000000-0000-0000-0000-00000000000b'$$,
             'profile hidden pending review', 'skrytou fotku nejde změnit');
-- timezone klient od #33 nemění (nastavuje ho ingest)
select t_err($$update public.profiles set timezone = 'Europe/London' where id = '00000000-0000-0000-0000-00000000000b'$$,
             'permission denied', 'timezone klient nemění (#33)');
select t_as('0a');
update public.profiles set display_name = 'Adámek' where id = '00000000-0000-0000-0000-00000000000a';
select t_ok((select display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000a') = 'Adámek', 'ostatní profily beze změny');
reset role;
select private.resolve_report((select id from public.reports where target_id = '00000000-0000-0000-0000-00000000000b' limit 1), 'dismiss');
select t_ok((select display_name = 'Jakub Hrubý' and avatar_path = '00000000-0000-0000-0000-00000000000b/a.jpg'
             from public.profiles where id = '00000000-0000-0000-0000-00000000000b'), 'profil: dismiss vrátí jméno i fotku');
set role authenticated;
select t_as('0b');
update public.profiles set display_name = 'Jakub' where id = '00000000-0000-0000-0000-00000000000b';
select t_ok((select display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000b') = 'Jakub', 'po dismiss jméno zase jde změnit');
reset role;

-- =====================================================================
-- Sázka: skrytá, výzva mezitím skončí, dismiss vrátí sázku a doplní dluh
-- =====================================================================
set role authenticated;
select t_as('0c'); select public.report_content('challenge', '40000000-0000-0000-0000-000000000001', 'hate');
select t_as('0d'); select public.report_content('challenge', '40000000-0000-0000-0000-000000000001', 'hate');
select t_as('0f'); select public.report_content('challenge', '40000000-0000-0000-0000-000000000001', 'hate');
select t_ok((select stake from public.challenges where id = '40000000-0000-0000-0000-000000000001') is null, 'sázka skrytá');
select t_ok((select status from public.challenges where id = '40000000-0000-0000-0000-000000000001') = 'active', 'výzva běží dál');
reset role;
update public.challenges set status = 'finished' where id = '40000000-0000-0000-0000-000000000001';
update public.challenge_participants set result = case when user_id = '00000000-0000-0000-0000-00000000000b'
  then 'win'::public.challenge_result else 'loss'::public.challenge_result end
where challenge_id = '40000000-0000-0000-0000-000000000001';
select private.resolve_report((select id from public.reports where target_id = '40000000-0000-0000-0000-000000000001' limit 1), 'dismiss');
select t_ok((select stake from public.challenges where id = '40000000-0000-0000-0000-000000000001') = 'sprostá sázka', 'dismiss vrátí sázku');
select t_ok((select count(*) from public.debts where challenge_id = '40000000-0000-0000-0000-000000000001'
             and debtor_id = '00000000-0000-0000-0000-00000000000a' and stake = 'sprostá sázka') = 1, 'dismiss doplní chybějící dluh');

-- =====================================================================
-- remove: karta bez textu a fotky je zase vidět
-- =====================================================================
set role authenticated;
select t_as('0c'); select public.report_content('post', '20000000-0000-0000-0000-0000000000b2', 'hate');
select t_as('0d'); select public.report_content('post', '20000000-0000-0000-0000-0000000000b2', 'hate');
select t_as('0f'); select public.report_content('post', '20000000-0000-0000-0000-0000000000b2', 'hate');
-- Adam nehlásil, přesto kartu nevidí
select t_as('0a');
select t_ok((select count(*) from public.posts where id = '20000000-0000-0000-0000-0000000000b2') = 0, 'druhá karta skrytá');
reset role;
select private.resolve_report((select id from public.reports where target_id = '20000000-0000-0000-0000-0000000000b2' limit 1), 'remove');
set role authenticated;
select t_as('0a');
select t_ok((select title is null and hidden_at is null from public.posts where id = '20000000-0000-0000-0000-0000000000b2'),
            'remove: karta bez textu zase vidět');
reset role;

-- =====================================================================
-- Práh z app_config, klient nevidí hidden_content ani nevolá funkce
-- =====================================================================
insert into private.app_config values ('auto_hide_threshold', '2');
set role authenticated;
-- (stejní lidé po dismiss znovu nahlásit nejdou – unikátní hlášení → bere se Karolínin komentář)
select t_as('0a'); select public.report_content('comment', '30000000-0000-0000-0000-0000000000c1', 'spam');
select t_as('0d'); select public.report_content('comment', '30000000-0000-0000-0000-0000000000c1', 'spam');
select t_as('0c');
select t_ok((select hidden_at is not null from public.comments where id = '30000000-0000-0000-0000-0000000000c1'), 'práh 2 z app_config');
select t_err($$select * from private.hidden_content$$, 'permission denied', 'klient nečte hidden_content');
select t_err($$select private.hide_content('post', '20000000-0000-0000-0000-0000000000a1')$$, 'permission denied', 'klient neskrývá');
select t_err($$select private.unhide_content('comment', '30000000-0000-0000-0000-0000000000b1', true)$$, 'permission denied', 'klient neodkrývá');
select t_err($$update public.posts set hidden_at = null where id = '20000000-0000-0000-0000-0000000000b1'$$,
             'permission denied', 'autor si skrytí nezruší');
reset role;

-- ban přes skrytý komentář: komentář pryč, záznam o skrytí pryč
select private.resolve_report((select id from public.reports where target_id = '30000000-0000-0000-0000-0000000000c1' and status = 'open' limit 1), 'ban');
select t_ok(not exists (select 1 from public.comments where id = '30000000-0000-0000-0000-0000000000c1'), 'ban: komentář smazán');
select t_ok((select banned_at is not null from public.profiles where id = '00000000-0000-0000-0000-00000000000c'), 'ban: autorka zabanovaná');
select t_ok(not exists (select 1 from private.hidden_content), 'ban: záznam o skrytí pryč');

\echo auto_hide_test: vše prošlo
