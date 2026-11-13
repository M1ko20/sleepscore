-- #37 pravidla z code review (domluveno s Adamem 2026-11-12):
-- 1) Smazání účtu v rozjetém souboji = kontumační výhra soupeři.
-- 2) Odznaky za noc se při změně noci / tagu alkohol přepočítají (i odeberou).
-- 3) Vzájemná bilance ve všichni proti všem: jen vítěz proti poraženým.
-- 4) Výzva max. 30 dní, čekající výzva po 7 dnech vyprší.
-- 5) Milník série jen jednou za sérii.

-- =====================================================================
-- 1) Kontumace
-- =====================================================================
alter table public.challenges add column forfeit boolean not null default false;

create or replace function public.delete_my_account()
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_me  uuid := auth.uid();
  r     record;
  v_opp uuid;
begin
  if v_me is null then raise exception 'not authenticated'; end if;

  -- Rozjetý souboj (už se hraje) → kontumační výhra soupeři: výhra do MMA a pozvánka.
  -- Ovečka a dluh odpadnou – moje účast a data jdou kaskádou pryč.
  for r in
    select x.id from public.challenges x
    where x.status = 'active' and x.type = 'duel'
      and x.start_date <= (now() at time zone x.timezone)::date
      and exists (select 1 from public.challenge_participants cp
                  where cp.challenge_id = x.id and cp.user_id = v_me and cp.status = 'accepted')
    for update
  loop
    select user_id into v_opp from public.challenge_participants
    where challenge_id = r.id and user_id <> v_me and status = 'accepted';
    if v_opp is null then continue; end if;   -- bez soupeře → zruší se níž

    update public.challenge_participants p
    set result = case when p.user_id = v_me then 'loss' else 'win' end::public.challenge_result,
        final_avg = (select round(avg(d.score), 2) from public.challenge_day_scores d
                     where d.challenge_id = r.id and d.user_id = p.user_id)
    where p.challenge_id = r.id and p.status = 'accepted';
    update public.challenges set status = 'finished', finalized_at = now(), forfeit = true where id = r.id;
    -- notifikaci výsledku vytvořil trigger; text „Soupeř smazal účet. Výhra kontumačně.“
    update public.notifications set payload = payload || '{"forfeit": true}'::jsonb
    where challenge_id = r.id and kind = 'challenge_result' and user_id = v_opp;
    update public.profiles set invites_available = invites_available + 1 where id = v_opp;
  end loop;

  -- Neuzavřené souboje se mnou, které ještě nezačaly → zrušit.
  -- Skupinové běží dál beze mě (účastník zmizí kaskádou).
  update public.challenges c set status = 'cancelled'
  where c.status in ('pending', 'active') and c.type = 'duel'
    and exists (select 1 from public.challenge_participants cp
                where cp.challenge_id = c.id and cp.user_id = v_me);
  -- Moje čekající skupinové výzvy (ještě nikdo nehrál) → zrušit.
  update public.challenges set status = 'cancelled'
  where creator_id = v_me and status = 'pending';

  -- auth.users → kaskádou profiles a vše navázané (noci, karty, komentáře, reakce,
  -- přátelství, účasti, dluhy, odznaky, pozvánky, push tokeny).
  delete from auth.users where id = v_me;
end;
$$;

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
    -- bez jména autora karty (skloňování); příjemce kartu zná, sám pod ní psal
    return v_actor || ' taky komentuje noc, pod kterou píšeš: ' || coalesce(p ->> 'text', '');

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
           || ', ' || (p ->> 'duration_days') || ' dní' || coalesce(', ' || (p ->> 'stake'), '') || '.';

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
    if p ? 'forfeit' then
      return 'Soupeř smazal účet. Výhra kontumačně.';
    end if;
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
               || case when v_cnt <= 4 then ' ovečky.' else ' oveček.' end;
      end if;
      return 'Vyhráno ' || v_num || '. ' || v_actor || ' přichází o ovečku.';
    when 'loss' then
      if p ->> 'other_result' = 'win' then
        return 'Prohra ' || v_num || '. ' || v_actor || ' bere tvoji ovečku.';
      end if;
      return 'Prohra ' || v_num || '.';   -- nahoře remíza, ovečky nikdo
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

-- =====================================================================
-- 2) Přepočet odznaků za noc
-- =====================================================================
-- Smaže odznaky noci, vyhodnotí znovu a co zůstalo, dostane zpět původní
-- datum a notifikace se pro ně neopakuje. Odebrané zmizí i ze zvonečku.
create function private.reaward_night(p_night uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_codes constant text[] := array['coma', 'zombie', 'night_shift', 'didnt_move', 'deep_diver',
    'perfect_night', 'either_or', 'stolen_hour', 'new_year_survivor', 'despite_it', 'beer_won', 'swiss_watch'];
  v_user uuid;
  v_old  jsonb;
begin
  select user_id into v_user from public.nights where id = p_night;
  if not found then return; end if;

  select coalesce(jsonb_object_agg(code, earned_at), '{}'::jsonb) into v_old
  from public.user_achievements where night_id = p_night and code = any(v_codes);
  delete from public.user_achievements where night_id = p_night and code = any(v_codes);

  perform set_config('bedrival.reaward', v_old::text, true);
  perform private.award_night_achievements(p_night);
  perform set_config('bedrival.reaward', '', true);

  update public.user_achievements ua set earned_at = (v_old ->> ua.code)::timestamptz
  where ua.night_id = p_night and v_old ? ua.code;

  delete from public.notifications n
  where n.user_id = v_user and n.kind = 'achievement'
    and n.post_id = (select id from public.posts where night_id = p_night)
    and v_old ? (n.payload ->> 'code')
    and not exists (select 1 from public.user_achievements ua
                    where ua.night_id = p_night and ua.code = n.payload ->> 'code');
end;
$$;

create or replace function private.on_achievement_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_skip text := nullif(current_setting('bedrival.reaward', true), '');
begin
  -- přepočet noci: odznak, který už měl, se nehlásí znovu
  if v_skip is not null and new.night_id is not null and v_skip::jsonb ? new.code then
    return null;
  end if;
  insert into public.notifications (user_id, kind, post_id, challenge_id, payload)
  values (new.user_id, 'achievement',
          (select id from public.posts where night_id = new.night_id),
          new.challenge_id,
          jsonb_build_object('code', new.code,
                             'times', (select count(*) from public.user_achievements
                                       where user_id = new.user_id and code = new.code)));
  return null;
end;
$$;

create or replace function public.after_night_ingest(p_night uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid;
  v_res  jsonb;
begin
  select user_id into v_user from public.nights where id = p_night;
  if not found then return null; end if;
  perform private.reaward_night(p_night);
  perform private.recompute_streak(v_user);
  select jsonb_build_object(
           'current_streak', s.current_streak,
           'best_streak', s.best_streak,
           'new_achievements', coalesce((select jsonb_agg(ua.code) from public.user_achievements ua
                                         where ua.user_id = v_user and ua.earned_at = now()), '[]'::jsonb))
    into v_res
  from public.user_stats s where s.user_id = v_user;
  return v_res;
end;
$$;

-- Tag alkohol přidaný i odebraný → přepočet (Navzdory / Pivo vyhrálo).
create or replace function private.on_night_tag()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(new.tag, old.tag) = 'alcohol' then
    perform private.reaward_night(coalesce(new.night_id, old.night_id));
  end if;
  return null;
end;
$$;
drop trigger night_tags_award on public.night_tags;
create trigger night_tags_award after insert or delete on public.night_tags
  for each row execute function private.on_night_tag();

-- =====================================================================
-- 3) Vzájemná bilance: vítěz proti každému poraženému, remíza mezi
--    remizujícími. Poražení mezi sebou nic.
-- =====================================================================
create or replace view public.head_to_head with (security_invoker = true) as
select me.user_id,
       opp.user_id as opponent_id,
       count(*) filter (where me.result = 'win'  and opp.result = 'loss') as wins,
       count(*) filter (where me.result = 'loss' and opp.result = 'win')  as losses,
       count(*) filter (where me.result = 'draw' and opp.result = 'draw') as draws
from public.challenges c
join public.challenge_participants me  on me.challenge_id  = c.id and me.status  = 'accepted'
join public.challenge_participants opp on opp.challenge_id = c.id and opp.status = 'accepted'
                                       and opp.user_id <> me.user_id
where c.status = 'finished' and c.type <> 'team_goal'
  and ((me.result = 'win' and opp.result = 'loss') or (me.result = 'loss' and opp.result = 'win')
       or (me.result = 'draw' and opp.result = 'draw'))
group by me.user_id, opp.user_id;

-- =====================================================================
-- 4) Délka a vypršení výzev
-- =====================================================================
-- not valid: starší delší výzvy zůstanou, nové max. 30 dní
alter table public.challenges add constraint challenges_duration_max check (duration_days <= 30) not valid;

create function private.expire_pending_challenges(p_days int default 7)
returns int language plpgsql security definer set search_path = '' as $$
declare
  n int;
begin
  update public.challenges set status = 'cancelled'
  where status = 'pending' and created_at < now() - make_interval(days => p_days);
  get diagnostics n = row_count;
  return n;
end;
$$;
select cron.schedule('expire-pending-challenges', '40 3 * * *', $$select private.expire_pending_challenges()$$);

-- =====================================================================
-- 5) Milník série jen jednou za sérii
-- =====================================================================
create or replace function private.recompute_streak(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_tz        text;
  v_now       timestamp;
  v_asof      date;
  r           record;
  v_cur       int := 0;
  v_best      int := 0;
  v_freeze    date;
  v_last_good date;
  v_start     date;   -- první noc běžící série
begin
  select timezone into v_tz from public.profiles where id = p_user;
  if not found then return; end if;
  v_now := now() at time zone v_tz;
  -- dnešní noc se počítá, když už dorazila, nebo když je po 14:00
  v_asof := case
    when v_now::time >= '14:00'
      or exists (select 1 from public.nights where user_id = p_user and night_date = v_now::date)
    then v_now::date else v_now::date - 1 end;

  for r in
    with n as (
      select id, night_date, total_sleep_min, private.minutes_from_noon(sleep_start, v_tz) as sm
      from public.nights where user_id = p_user and night_date <= v_asof
    ), w as (
      select n.*,
             avg(sm)  over (order by night_date rows between 14 preceding and 1 preceding) as avg_sm,
             count(*) over (order by night_date rows between 14 preceding and 1 preceding) as cnt
      from n
    )
    select d::date as day, w.id as night_id,
           coalesce(w.total_sleep_min >= 360 and (w.cnt < 3 or abs(w.sm - w.avg_sm) <= 30), false) as good
    from generate_series((select min(night_date) from n), v_asof, interval '1 day') d
    left join w on w.night_date = d::date
    order by 1
  loop
    if r.good then
      if v_cur = 0 then v_start := r.day; end if;
      v_cur := v_cur + 1;
      v_last_good := r.day;
      -- milníky jen za poslední týden (ať zpětný přepočet neudílí staré)
      -- … a jen jednou za sérii (zpětné nahrání může milník posunout na jinou noc).
      -- Jiná série by milník v okně posledního týdne trefit nestihla.
      if v_cur in (7, 30, 100) and r.day >= v_asof - 7 and not exists (
        select 1 from public.user_achievements ua join public.nights x on x.id = ua.night_id
        where ua.user_id = p_user and ua.code = 'streak_' || v_cur and x.night_date >= v_start
      ) then
        if private.award(p_user, 'streak_' || v_cur, r.night_id) and v_cur in (30, 100) then
          update public.profiles set invites_available = invites_available + 1 where id = p_user;
        end if;
      end if;
    elsif v_cur > 0 and v_freeze is distinct from date_trunc('week', r.day)::date then
      v_freeze := date_trunc('week', r.day)::date;
    else
      v_cur := 0;
    end if;
    v_best := greatest(v_best, v_cur);
  end loop;

  insert into public.user_stats (user_id, current_streak, best_streak, last_streak_date, freeze_used_week, updated_at)
  values (p_user, v_cur, v_best, v_last_good, v_freeze, now())
  on conflict (user_id) do update set
    current_streak = excluded.current_streak,
    best_streak = excluded.best_streak,
    last_streak_date = excluded.last_streak_date,
    freeze_used_week = excluded.freeze_used_week,
    updated_at = excluded.updated_at;
end;
$$;

revoke execute on function private.reaward_night(uuid), private.expire_pending_challenges(int)
from public, anon, authenticated;
