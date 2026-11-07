-- =====================================================================
-- Notifikace: „Kamarád tě předbíhá“ a komentáře pro celé vlákno. Issue #15.
--
-- 1) challenge_overtaken – soupeř v běžící výzvě (duel, všichni proti všem)
--    tě přeskočí v průběžném průměru. Trigger na challenge_day_scores, max.
--    1 notifikace na výzvu a příjemce za den (den v pásmu zakladatele).
-- 2) Komentář dostane kromě autora karty i každý, kdo už pod kartu psal
--    (stejný kind 'comment', payload.thread = true → jiný text).
--
-- Vše v DB (triggery), žádná Edge Function.
-- =====================================================================

alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in (
  'reaction', 'comment',
  'friend_request', 'friend_accepted',
  'challenge_invite', 'challenge_response', 'challenge_started',
  'challenge_ending', 'challenge_result', 'debt_settled', 'challenge_overtaken',
  'achievement', 'night_ready', 'weekly_recap'));
-- category: challenge_overtaken spadne do 'challenges' (větev else), komentáře
-- ve vlákně jsou 'comment' → 'comments'. Generovaný sloupec se nemění.

-- Max. 1 „předbíhá“ na výzvu, příjemce a den.
create unique index notifications_overtaken_key on public.notifications
  (user_id, challenge_id, (payload ->> 'day')) where kind = 'challenge_overtaken';

-- ---------------------------------------------------------------------
-- Průběžný průměr hráče ve výzvě – stejně jako appka (ChallengeModels):
-- uplynulé dny (do včerejška) se počítají vždy, chybějící = 0; dnešek
-- (a cokoliv dál) jen když už je nahraný. NULL = zatím žádný odehraný den.
-- „Dnes“ = datum v pásmu zakladatele.
-- ---------------------------------------------------------------------
create function private.challenge_running_avg(p_challenge uuid, p_user uuid, p_today date)
returns numeric language sql stable security definer set search_path = '' as $$
  select case when x.n > 0 then x.s / x.n end
  from (
    select coalesce(sum(s.score), 0)::numeric as s,
           greatest(least(p_today - 1, c.end_date) - c.start_date + 1, 0)
             + count(s.day) filter (where s.day >= p_today) as n
    from public.challenges c
    left join public.challenge_day_scores s on s.challenge_id = c.id and s.user_id = p_user
    where c.id = p_challenge
    group by c.start_date, c.end_date
  ) x;
$$;

-- ---------------------------------------------------------------------
-- „X tě předbíhá“: po zápisu denního skóre (ingest) porovná průměr hráče
-- před a po zápisu s průměry soupeřů. Kdo byl předtím před ním a teď je
-- za ním, dostane notifikaci.
--   - jen běžící duel / všichni proti všem a jen do uzavření (14:00 posledního dne),
--   - jen skutečné noci (night_id) – nuly a doplnění při uzavírání nic neposílají,
--   - přepis stejným skóre (opakovaný sync) nic nedělá,
--   - zpětné nahrání posílá taky (je to skutečná změna pořadí), ale max. 1/den,
--   - mezi zablokovanými nic.
-- Přeskočení „půlnocí“ (soupeři chybí včerejší noc → 0) bez zápisu nehlásí.
-- ---------------------------------------------------------------------
create function private.on_day_score_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  c        public.challenges;
  v_tz     text;
  v_today  date;
  v_past   int;
  v_sum    numeric;
  v_future int;
  v_after  numeric;
  v_before numeric;
begin
  if new.night_id is null then return null; end if;
  if tg_op = 'UPDATE' then
    if new.score = old.score then return null; end if;
  end if;

  select * into c from public.challenges where id = new.challenge_id;
  if not found or c.status <> 'active' or c.type = 'team_goal' then return null; end if;
  select p.timezone into v_tz from public.profiles p where p.id = c.creator_id;
  v_tz := coalesce(v_tz, 'Europe/Prague');
  if now() >= ((c.end_date + time '14:00') at time zone v_tz) then return null; end if;
  if not exists (select 1 from public.challenge_participants
                 where challenge_id = c.id and user_id = new.user_id and status = 'accepted') then
    return null;
  end if;

  v_today := (now() at time zone v_tz)::date;
  v_past := greatest(least(v_today - 1, c.end_date) - c.start_date + 1, 0);
  select coalesce(sum(score), 0), count(*) filter (where day >= v_today)
    into v_sum, v_future
  from public.challenge_day_scores
  where challenge_id = c.id and user_id = new.user_id;

  v_after := case when v_past + v_future > 0 then v_sum / (v_past + v_future) end;
  if tg_op = 'INSERT' then
    v_sum := v_sum - new.score;
    if new.day >= v_today then v_future := v_future - 1; end if;
  else
    v_sum := v_sum - new.score + old.score;
  end if;
  v_before := case when v_past + v_future > 0 then v_sum / (v_past + v_future) end;

  if v_after is null or v_after <= coalesce(v_before, -1) then return null; end if;

  insert into public.notifications (user_id, kind, actor_id, challenge_id, payload)
  select o.user_id, 'challenge_overtaken', new.user_id, c.id,
         jsonb_build_object('type', c.type, 'day', v_today,
                            'actor_avg', round(v_after, 2), 'my_avg', round(o.avg, 2))
  from (
    select cp.user_id, private.challenge_running_avg(c.id, cp.user_id, v_today) as avg
    from public.challenge_participants cp
    where cp.challenge_id = c.id and cp.status = 'accepted' and cp.user_id <> new.user_id
  ) o
  where o.avg is not null
    and o.avg > coalesce(v_before, -1)     -- předtím byl soupeř přede mnou
    and v_after > o.avg                    -- teď jsem před ním
    and not private.is_blocked(o.user_id, new.user_id)
  on conflict do nothing;
  return null;
end;
$$;
create trigger challenge_day_scores_notify after insert or update of score on public.challenge_day_scores
  for each row execute function private.on_day_score_notify();

-- ---------------------------------------------------------------------
-- Komentáře: autor karty + všichni, kdo už pod kartu psali.
-- Ostatním ve vlákně jen pokud kartu pořád vidí (přítel autora karty,
-- kartu nenahlásili), nejsou zabanovaní a nemají blok s autorem komentáře.
-- ---------------------------------------------------------------------
create or replace function private.on_comment_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_owner uuid;
  v_text  text := left(new.body, 140);
begin
  select user_id into v_owner from public.posts where id = new.post_id and kind = 'night';
  if v_owner is null then return null; end if;

  if v_owner <> new.user_id then
    insert into public.notifications (user_id, kind, actor_id, post_id, comment_id, payload)
    values (v_owner, 'comment', new.user_id, new.post_id, new.id, jsonb_build_object('text', v_text));
  end if;

  insert into public.notifications (user_id, kind, actor_id, post_id, comment_id, payload)
  select t.user_id, 'comment', new.user_id, new.post_id, new.id,
         jsonb_build_object('text', v_text, 'thread', true, 'by_owner', new.user_id = v_owner)
  from (select distinct c.user_id from public.comments c
        where c.post_id = new.post_id and c.id <> new.id) t
  join public.profiles p on p.id = t.user_id and p.banned_at is null
  where t.user_id <> new.user_id
    and t.user_id <> v_owner
    and private.are_friends(t.user_id, v_owner)
    and not private.is_blocked(t.user_id, new.user_id)
    and not exists (select 1 from public.reports r
                    where r.reporter_id = t.user_id and r.target_kind = 'post' and r.target_id = new.post_id);
  return null;
end;
$$;

-- ---------------------------------------------------------------------
-- Text: nové větve pro komentáře ve vlákně a „předbíhá“. Zbytek beze změny.
-- ---------------------------------------------------------------------
create or replace function public.notification_text(n public.notifications)
returns text language plpgsql stable security invoker set search_path = '' as $$
declare
  v_actor text;
  v_name  text;
  v_score smallint;
  v_card  boolean;
  p       jsonb := n.payload;
  v_num   text;
  v_other int;
  v_cnt   int;
  v_a     numeric;
  v_b     numeric;
  v_fmt   text;
begin
  select display_name into v_actor from public.profiles where id = n.actor_id;
  v_actor := coalesce(v_actor, 'Někdo');

  case n.kind
  when 'reaction' then
    v_other := n.count - 1;
    if v_other <= 0 then
      return v_actor || ' reaguje na tvoji noc.';
    end if;
    return v_actor || ' a ' || v_other
           || case when v_other <= 4 then ' další' else ' dalších' end
           || ' reagují na tvoji noc.';

  when 'comment' then
    if not coalesce((p ->> 'thread')::boolean, false) then
      return v_actor || ' komentuje tvoji noc: ' || coalesce(p ->> 'text', '');
    end if;
    if coalesce((p ->> 'by_owner')::boolean, false) then
      return v_actor || ' odpovídá pod svojí nocí: ' || coalesce(p ->> 'text', '');
    end if;
    -- jméno autora karty (živě; kartu už nevidím → bez jména)
    select pr.display_name into v_name
    from public.posts po join public.profiles pr on pr.id = po.user_id
    where po.id = n.post_id;
    if v_name is null then
      return v_actor || ' taky komentuje: ' || coalesce(p ->> 'text', '');
    end if;
    return v_actor || ' taky komentuje noc, kterou má ' || v_name || ': ' || coalesce(p ->> 'text', '');

  when 'friend_request' then
    return v_actor || ' ti posílá žádost o přátelství.';

  when 'friend_accepted' then
    if (p ->> 'via_invite')::boolean then
      return v_actor || ' je tu přes tvoji pozvánku.';
    end if;
    return v_actor || ' přijímá žádost o přátelství.';

  when 'challenge_invite' then
    return v_actor
      || case p ->> 'type'
           when 'duel' then ' tě vyzývá: '
           when 'free_for_all' then ' tě zve do výzvy všichni proti všem: '
           else ' tě zve do společného cíle ' || (p ->> 'target_score') || ': '
         end
      || (p ->> 'duration_days') || ' dní'
      || coalesce(', ' || (p ->> 'stake'), '') || '.';

  when 'challenge_response' then
    if (p ->> 'accepted')::boolean then
      return v_actor || ' jde do toho.';
    end if;
    return v_actor || ' výzvu odmítá.';

  when 'challenge_started' then
    if p ->> 'type' = 'duel' and n.actor_id is not null then
      return v_actor || ' výzvu přijímá. Start ' || to_char((p ->> 'start_date')::date, 'FMDD. FMMM.')
             || ', ' || (p ->> 'duration_days') || ' dní.';
    end if;
    return 'Výzva startuje ' || to_char((p ->> 'start_date')::date, 'FMDD. FMMM.')
           || '. ' || (p ->> 'duration_days') || ' dní' || coalesce(', ' || (p ->> 'stake'), '') || '.';

  when 'challenge_overtaken' then
    v_a := (p ->> 'actor_avg')::numeric;
    v_b := (p ->> 'my_avg')::numeric;
    -- na 1 desetinné místo by vyšlo stejně → ukázat 2
    v_fmt := case when round(v_a, 1) = round(v_b, 1) then 'FM990.00' else 'FM990.0' end;
    return v_actor || ' tě předbíhá '
           || case when p ->> 'type' = 'duel' then 'v souboji' else 've výzvě' end || '. '
           || replace(to_char(v_a, v_fmt), '.', ',') || ' : ' || replace(to_char(v_b, v_fmt), '.', ',') || '.';

  when 'challenge_ending' then
    v_num := replace(to_char(abs((p ->> 'diff')::numeric), 'FM990.0'), '.', ',');
    return 'Zítra konec. ' || case p ->> 'mode'
      when 'lead'  then 'Vedeš o ' || v_num || ' bodu.'
      when 'trail' then 'Prohráváš o ' || v_num || ' bodu.'
      when 'tie'   then 'Je to nastejno.'
      else 'Skupina má ' || replace(to_char((p ->> 'avg')::numeric, 'FM990.0'), '.', ',')
           || ', cíl je ' || (p ->> 'target_score') || '.'
    end;

  when 'challenge_result' then
    v_num := replace(to_char((p ->> 'my_avg')::numeric, 'FM990.0'), '.', ',')
             || ' : ' || replace(to_char((p ->> 'other_avg')::numeric, 'FM990.0'), '.', ',');
    if p ->> 'type' = 'team_goal' then
      return case when p ->> 'result' = 'win' then 'Cíl splněn. ' else 'Cíl nesplněn. ' end
             || 'Skupina ' || replace(to_char((p ->> 'my_avg')::numeric, 'FM990.0'), '.', ',')
             || ', cíl ' || (p ->> 'target_score') || '.';
    end if;
    case p ->> 'result'
    when 'win' then
      v_cnt := coalesce((p ->> 'souls')::int, 1);
      if v_cnt > 1 then
        return 'Vyhráno ' || v_num || '. Bereš ' || v_cnt
               || case when v_cnt <= 4 then ' duše.' else ' duší.' end;
      end if;
      return 'Vyhráno ' || v_num || '. ' || v_actor || ' přichází o duši.';
    when 'loss' then
      if p ->> 'other_result' = 'win' then
        return 'Prohra ' || v_num || '. ' || v_actor || ' bere tvoji duši.';
      end if;
      return 'Prohra ' || v_num || '.';   -- nahoře remíza, duše nikdo
    else
      return 'Remíza ' || v_num || '.';
    end case;

  when 'debt_settled' then
    return v_actor || ' hlásí splaceno: ' || coalesce(p ->> 'stake', 'sázka') || '.';

  when 'achievement' then
    select name into v_name from public.achievements where code = p ->> 'code';
    v_name := coalesce(v_name, p ->> 'code');
    if coalesce((p ->> 'times')::int, 1) > 1 then
      return v_name || '. Zase.';
    end if;
    return 'Nový odznak: ' || v_name || '.';

  when 'night_ready' then
    select ni.score, (po.title is not null or po.body is not null)
      into v_score, v_card
    from public.posts po join public.nights ni on ni.id = po.night_id
    where po.id = n.post_id;
    if v_score is null then return 'Noc je tady.'; end if;
    return 'Tvoje noc: ' || v_score || '.' || case when v_card then '' else ' Doplň komentář.' end;

  when 'weekly_recap' then
    v_cnt := (p ->> 'nights')::int;
    return 'Minulý týden v číslech: průměr '
           || replace(to_char((p ->> 'avg_score')::numeric, 'FM990'), '.', ',') || ', '
           || v_cnt || case when v_cnt = 1 then ' noc.' when v_cnt <= 4 then ' noci.' else ' nocí.' end;

  else
    return '';
  end case;
end;
$$;

revoke execute on function
  private.challenge_running_avg(uuid, uuid, date),
  private.on_day_score_notify(),
  private.on_comment_notify()
from public, anon, authenticated;
