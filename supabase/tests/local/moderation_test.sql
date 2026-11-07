-- Moderace: blokování, nahlášení, upozornění, ban. Spouští run.sh.
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

-- Data: A–B, A–C, B–C přátelé. B má noc s kartou, A ji komentuje, C reaguje.
insert into auth.users (id) values
  ('00000000-0000-0000-0000-00000000000a'),
  ('00000000-0000-0000-0000-00000000000b'),
  ('00000000-0000-0000-0000-00000000000c');
insert into public.profiles (id, username, display_name) values
  ('00000000-0000-0000-0000-00000000000a', 'adam', 'Adam'),
  ('00000000-0000-0000-0000-00000000000b', 'jakub', 'Jakub'),
  ('00000000-0000-0000-0000-00000000000c', 'karolina', 'Karolína');
insert into public.friendships (user_a, user_b, requested_by, status) values
  ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000a', 'accepted'),
  ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-00000000000a', 'accepted'),
  ('00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-00000000000b', 'accepted');
insert into public.nights (id, user_id, night_date, sleep_start, sleep_end, total_sleep_min, score) values
  ('10000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b', current_date,
   now() - interval '8 hours', now(), 470, 80),
  ('10000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', current_date,
   now() - interval '8 hours', now(), 470, 80);
insert into public.posts (id, kind, user_id, night_id, title, photo_path) values
  ('20000000-0000-0000-0000-00000000000b', 'night', '00000000-0000-0000-0000-00000000000b',
   '10000000-0000-0000-0000-00000000000b', 'urážka', '00000000-0000-0000-0000-00000000000b/x.jpg'),
  ('20000000-0000-0000-0000-00000000000a', 'night', '00000000-0000-0000-0000-00000000000a',
   '10000000-0000-0000-0000-00000000000a', 'Adamova noc', null);
insert into public.comments (id, post_id, user_id, body) values
  ('30000000-0000-0000-0000-0000000000a1', '20000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000a', 'od Adama'),
  ('30000000-0000-0000-0000-0000000000c1', '20000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000c', 'od Karolíny'),
  ('30000000-0000-0000-0000-0000000000b1', '20000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b', 'Jakub u Adama');
insert into public.reactions (post_id, user_id, kind) values
  ('20000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b', 'zombie');
-- čekající souboj B → A a čekající skupinová výzva založená A s pozvaným B a C
insert into public.challenges (id, type, creator_id, duration_days, status) values
  ('40000000-0000-0000-0000-000000000001', 'duel', '00000000-0000-0000-0000-00000000000b', 7, 'pending'),
  ('40000000-0000-0000-0000-000000000002', 'free_for_all', '00000000-0000-0000-0000-00000000000a', 7, 'pending');
update public.challenges set stake = 'prohraný platí pivo' where id = '40000000-0000-0000-0000-000000000001';
insert into public.challenge_participants (challenge_id, user_id, status) values
  ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'accepted'),
  ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'invited'),
  ('40000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'accepted'),
  ('40000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000b', 'accepted'),
  ('40000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000c', 'invited');
insert into private.app_config values ('report_webhook_url', 'https://ntfy.sh/tajne-tema'),
                                      ('report_webhook_format', 'ntfy');

-- =====================================================================
-- Hlášení (Adam)
-- =====================================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);

select t_err($$select * from public.reports$$, 'permission denied', 'klient nečte tabulku reports');
select t_err($$insert into public.reports (target_kind, target_id, reason, snapshot) values ('post', gen_random_uuid(), 'spam', '{}')$$,
             'permission denied', 'klient nezapisuje do reports přímo');
select t_err($$select public.report_content('post', '20000000-0000-0000-0000-00000000000a', 'spam')$$,
             'cannot report yourself', 'vlastní kartu nahlásit nejde');
select t_err($$select public.report_content('comment', gen_random_uuid(), 'spam')$$,
             'content not found', 'neexistující komentář');
select t_err($$select public.report_content('post', '20000000-0000-0000-0000-00000000000b', 'nesmysl')$$,
             'reports_reason_check', 'důvod jen z pevného seznamu');

select t_ok((select count(*) from public.posts where id = '20000000-0000-0000-0000-00000000000b') = 1, 'před hlášením vidím Jakubovu kartu');
select public.report_content('post', '20000000-0000-0000-0000-00000000000b', 'harassment', '  nadávky v názvu ');
select t_ok((select count(*) from public.posts where id = '20000000-0000-0000-0000-00000000000b') = 0, 'nahlášená karta se mi skryla');
select public.report_content('post', '20000000-0000-0000-0000-00000000000b', 'spam');  -- podruhé = stejné hlášení
select t_ok((select count(*) from public.comments where id = '30000000-0000-0000-0000-0000000000c1') = 1, 'komentář Karolíny vidím');
select public.report_content('comment', '30000000-0000-0000-0000-0000000000c1', 'spam');
select t_ok((select count(*) from public.comments where id = '30000000-0000-0000-0000-0000000000c1') = 0, 'nahlášený komentář se mi skryl');
select public.report_content('profile', '00000000-0000-0000-0000-00000000000c', 'other', 'fotka');
select public.report_content('challenge', '40000000-0000-0000-0000-000000000001', 'hate');

reset role;
select t_ok((select count(*) from public.reports) = 4, '4 hlášení (opakované se nezdvojí)');
select t_ok((select note from public.reports where target_kind = 'post') = 'nadávky v názvu', 'poznámka oříznutá');
select t_ok((select reason from public.reports where target_kind = 'post') = 'harassment', 'první hlášení se nepřepíše');
select t_ok((select snapshot ->> 'title' from public.reports where target_kind = 'post') = 'urážka', 'snapshot obsahu');
select t_ok((select reported_user_id from public.reports where target_kind = 'challenge') = '00000000-0000-0000-0000-00000000000b', 'u výzvy je nahlášený zakladatel');
select t_ok((select count(*) from net.requests) = 4, 'upozornění odešlo 4×');
select t_ok((select url from net.requests limit 1) = 'https://ntfy.sh', 'ntfy: kořen serveru');
select t_ok((select body ->> 'topic' from net.requests limit 1) = 'tajne-tema', 'ntfy: téma v těle');
select t_ok((select body::text from net.requests order by id limit 1) not like '%urážka%', 'upozornění neobsahuje obsah');
-- Karolína svoje hlášení nemá → Jakubovu kartu vidí
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
select t_ok((select count(*) from public.posts where id = '20000000-0000-0000-0000-00000000000b') = 1, 'ostatní nahlášenou kartu dál vidí');
reset role;

-- Připomínka po 12 h (jen jednou)
update public.reports set created_at = now() - interval '13 hours' where target_kind = 'post';
select t_ok(private.remind_open_reports() = 1, 'připomínka: 1 hlášení přes 12 h');
select t_ok(private.remind_open_reports() = 0, 'připomínka se neopakuje');
select t_ok((select count(*) from net.requests) = 5, 'připomínka odešla');
select t_ok(exists (select 1 from cron.job where jobname = 'report-reminder'), 'cron úloha report-reminder');

-- Bez URL se nic neposílá a hlášení se uloží
delete from private.app_config;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select public.report_content('comment', '30000000-0000-0000-0000-0000000000a1', 'spam');
reset role;
select t_ok((select count(*) from net.requests) = 5, 'bez nastavené URL nic neodešlo');

-- Limit 20 hlášení za den
insert into public.reports (reporter_id, target_kind, target_id, reason, snapshot)
select '00000000-0000-0000-0000-00000000000c', 'profile', gen_random_uuid(), 'spam', '{}' from generate_series(1, 20);
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
select t_err($$select public.report_content('post', '20000000-0000-0000-0000-00000000000b', 'spam')$$,
             'too many reports', 'limit 20 hlášení / den');
reset role;
delete from public.reports where reporter_id = '00000000-0000-0000-0000-00000000000c';

-- =====================================================================
-- Blokování: Adam blokuje Jakuba
-- =====================================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select t_err($$insert into public.blocks values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b')$$,
             'permission denied', 'blok jen přes RPC');
select t_err($$select public.block_user('00000000-0000-0000-0000-00000000000a')$$, 'cannot block yourself', 'sebe blokovat nejde');
select t_ok((select count(*) from public.reactions where user_id = '00000000-0000-0000-0000-00000000000b') = 1, 'před blokem vidím Jakubovu reakci');
select public.block_user('00000000-0000-0000-0000-00000000000b');
select public.block_user('00000000-0000-0000-0000-00000000000b');  -- idempotentní
select t_ok((select count(*) from public.blocks) = 1, 'blok vidím');
select t_ok((select count(*) from public.friendships where '00000000-0000-0000-0000-00000000000b' in (user_a, user_b)) = 0, 'přátelství zrušené');
select t_ok((select count(*) from public.comments where user_id = '00000000-0000-0000-0000-00000000000b') = 0, 'Jakubovy komentáře nevidím');
select t_ok((select count(*) from public.reactions where user_id = '00000000-0000-0000-0000-00000000000b') = 0, 'Jakubovy reakce nevidím');
select t_ok((select count(*) from public.nights where user_id = '00000000-0000-0000-0000-00000000000b') = 0, 'Jakubovy noci nevidím');
select t_err($$select public.send_friend_request('00000000-0000-0000-0000-00000000000b')$$,
             'you blocked this user', 'žádost blokovanému: nejdřív odblokuj');
reset role;
select t_ok((select status from public.challenges where id = '40000000-0000-0000-0000-000000000001') = 'cancelled', 'čekající souboj zrušen');
select t_ok((select status from public.challenge_participants where challenge_id = '40000000-0000-0000-0000-000000000002'
             and user_id = '00000000-0000-0000-0000-00000000000b') = 'declined', 'z mé čekající skupinové výzvy vyřazen');
select t_ok((select status from public.challenge_participants where challenge_id = '40000000-0000-0000-0000-000000000002'
             and user_id = '00000000-0000-0000-0000-00000000000c') = 'invited', 'ostatní účastníci beze změny');

-- Jakub (blokovaný)
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select t_ok((select count(*) from public.blocks) = 0, 'blokovaný řádek bloku nevidí');
select t_err($$select public.send_friend_request('00000000-0000-0000-0000-00000000000a')$$, 'not allowed', 'blokovaný nemůže poslat žádost');
select t_err($$select public.create_challenge('duel', array['00000000-0000-0000-0000-00000000000a']::uuid[], 7)$$,
             'is not a friend', 'blokovaný nemůže vyzvat');
select t_ok((select count(*) from public.posts where user_id = '00000000-0000-0000-0000-00000000000a') = 0, 'blokovaný nevidí moje karty');
select t_err($$insert into public.comments (post_id, user_id, body) values ('20000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b', 'ahoj')$$,
             'row-level security', 'blokovaný nemůže komentovat');
select t_err($$insert into public.reactions (post_id, user_id, kind) values ('20000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b', 'beer')$$,
             'row-level security', 'blokovaný nemůže reagovat');
select t_ok((select count(*) from public.comments where user_id = '00000000-0000-0000-0000-00000000000a') = 0, 'blokovaný nevidí moje komentáře ani u třetích');
reset role;

-- Karolína (přítel obou) vidí komentáře obou
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
select t_ok((select count(*) from public.comments) = 3, 'třetí strana vidí všechny komentáře');
reset role;

-- Odblokování: přátelství se neobnoví, žádost zase jde
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select public.unblock_user('00000000-0000-0000-0000-00000000000b');
select t_ok((select count(*) from public.blocks) = 0, 'odblokováno');
select t_ok(public.send_friend_request('00000000-0000-0000-0000-00000000000b') = 'pending', 'po odblokování žádost jde');
select t_ok((select count(*) from public.comments where user_id = '00000000-0000-0000-0000-00000000000b') = 1, 'po odblokování zase vidím jeho komentář u své karty');
reset role;

-- Blok přes hlášení (p_block)
delete from public.friendships where '00000000-0000-0000-0000-00000000000b' in (user_a, user_b) and status = 'pending';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
select public.report_content('profile', '00000000-0000-0000-0000-00000000000b', 'harassment', null, true);
select t_ok((select count(*) from public.blocks where blocked_id = '00000000-0000-0000-0000-00000000000b') = 1, 'hlášení s blokem zablokuje');
reset role;
select private.unban_user('00000000-0000-0000-0000-00000000000b');  -- no-op, jen že jde zavolat

-- Klient nevolá admin funkce
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select t_err($$select private.resolve_report(gen_random_uuid(), 'dismiss')$$, 'permission denied', 'klient nevyřizuje hlášení');
select t_err($$select private.ban_user('00000000-0000-0000-0000-00000000000b')$$, 'permission denied', 'klient nebanuje');
reset role;
set role anon;
select t_err($$select public.report_content('post', gen_random_uuid(), 'spam')$$, 'permission denied', 'anon nehlásí');
select t_err($$select public.block_user(gen_random_uuid())$$, 'permission denied', 'anon neblokuje');
reset role;

-- =====================================================================
-- Vyřízení: remove a ban
-- =====================================================================
select private.resolve_report((select id from public.reports where target_kind = 'comment'
                               and target_id = '30000000-0000-0000-0000-0000000000c1'), 'dismiss', 'v pohodě');
select t_ok((select status from public.reports where target_id = '30000000-0000-0000-0000-0000000000c1') = 'dismissed', 'dismiss');
select t_ok(exists (select 1 from public.comments where id = '30000000-0000-0000-0000-0000000000c1'), 'dismiss nic nemaže');

select private.resolve_report((select id from public.reports where target_kind = 'challenge'), 'remove');
select t_ok((select stake from public.challenges where id = '40000000-0000-0000-0000-000000000001') is null, 'remove: sázka smazaná');

-- Jakub má otevřenou noc a čekající výzvu, pak ban přes hlášení karty
insert into public.invites (code, inviter_id) values ('ABCDEFGH', '00000000-0000-0000-0000-00000000000b');
select private.resolve_report((select id from public.reports where target_kind = 'post'), 'ban', 'opakovaně');
select t_ok((select title from public.posts where id = '20000000-0000-0000-0000-00000000000b') is null, 'ban: obsah karty smazán');
select t_ok((select banned_at is not null from public.profiles where id = '00000000-0000-0000-0000-00000000000b'), 'ban: profiles.banned_at');
select t_ok((select banned_until = 'infinity' from auth.users where id = '00000000-0000-0000-0000-00000000000b'), 'ban: auth.users.banned_until');
select t_ok((select count(*) from public.friendships where '00000000-0000-0000-0000-00000000000b' in (user_a, user_b)) = 0, 'ban: přátelství pryč');
select t_ok((select count(*) from public.comments where user_id = '00000000-0000-0000-0000-00000000000b') = 0, 'ban: komentáře pryč');
select t_ok((select count(*) from public.invites where inviter_id = '00000000-0000-0000-0000-00000000000b') = 0, 'ban: nepoužité pozvánky pryč');
select t_ok((select status from public.reports where target_kind = 'post') = 'resolved', 'ban: hlášení vyřízené');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select t_ok((select count(*) from public.profiles) = 0, 'zabanovaný nevidí nic');
select t_err($$select public.send_friend_request('00000000-0000-0000-0000-00000000000c')$$, 'not a member', 'zabanovaný nemůže nic');
reset role;

select private.unban_user('00000000-0000-0000-0000-00000000000b');
select t_ok((select banned_at is null from public.profiles where id = '00000000-0000-0000-0000-00000000000b'), 'unban');

-- Smazání účtu hlásícího: hlášení zůstane bez reportera
delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';
select t_ok((select count(*) from public.reports where reporter_id is null) >= 1, 'po smazání hlásícího hlášení zůstane');
select t_ok((select count(*) from public.blocks) = 1, 'bloky smazaného zmizely, ostatní zůstaly');

\echo moderation_test: vše prošlo
