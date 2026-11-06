-- =====================================================================
-- Série, achievementy a uzavírání výzev.
-- Všechno běží v databázi (pg_cron + triggery), žádná Edge Function
-- navíc – nespotřebovává limity Free tieru.
-- =====================================================================

create function private.minutes_from_noon(ts timestamptz, tz text)
returns int language sql stable set search_path = '' as $$
  select ((extract(hour from ts at time zone tz) * 60
         + extract(minute from ts at time zone tz))::int - 720 + 1440) % 1440;
$$;

-- Udělí achievement; vrací true, když je nový.
create function private.award(p_user uuid, p_code text, p_night uuid default null, p_challenge uuid default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  n int;
begin
  insert into public.user_achievements (user_id, code, night_id, challenge_id)
  values (p_user, p_code, p_night, p_challenge)
  on conflict do nothing;
  get diagnostics n = row_count;
  return n > 0;
end;
$$;

-- ---------------------------------------------------------------------
-- Achievementy za noc
-- ---------------------------------------------------------------------
create function private.award_tag_achievements(p_night uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user  uuid;
  v_score smallint;
begin
  select n.user_id, n.score into v_user, v_score
  from public.nights n
  where n.id = p_night
    and exists (select 1 from public.night_tags t where t.night_id = n.id and t.tag = 'alcohol');
  if not found or v_score is null then return; end if;
  if v_score >= 85 then perform private.award(v_user, 'despite_it', p_night); end if;
  if v_score < 50 then perform private.award(v_user, 'beer_won', p_night); end if;
end;
$$;

create function private.award_night_achievements(p_night uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  n       public.nights;
  v_tz    text;
  v_sm    int;
  v_local timestamp;
  v_ok    boolean;
begin
  select * into n from public.nights where id = p_night;
  if not found then return; end if;
  select timezone into v_tz from public.profiles where id = n.user_id;
  v_sm := private.minutes_from_noon(n.sleep_start, v_tz);
  v_local := n.sleep_start at time zone v_tz;

  if n.total_sleep_min >= 600 then perform private.award(n.user_id, 'coma', n.id); end if;
  if n.total_sleep_min < 300 then perform private.award(n.user_id, 'zombie', n.id); end if;
  if v_sm >= 900 then perform private.award(n.user_id, 'night_shift', n.id); end if;          -- usnutí 3:00–11:59
  if n.wake_count = 0 and n.total_sleep_min >= 360 then perform private.award(n.user_id, 'didnt_move', n.id); end if;
  if n.deep_min >= 120 then perform private.award(n.user_id, 'deep_diver', n.id); end if;
  if n.score >= 95 then perform private.award(n.user_id, 'perfect_night', n.id); end if;
  if n.score < 30 then perform private.award(n.user_id, 'either_or', n.id); end if;
  -- noc na poslední neděli v březnu (přechod na letní čas)
  if extract(month from n.night_date) = 3 and extract(dow from n.night_date) = 0
     and extract(day from n.night_date) >= 25 then
    perform private.award(n.user_id, 'stolen_hour', n.id);
  end if;
  -- usnutí po 4:00 ráno 1. ledna
  if extract(month from n.night_date) = 1 and extract(day from n.night_date) = 1
     and v_local::date = n.night_date and v_local::time >= '04:00' then
    perform private.award(n.user_id, 'new_year_survivor', n.id);
  end if;

  perform private.award_tag_achievements(n.id);

  -- Švýcarské hodinky: 14 nocí v řadě s usnutím ±15 min od jejich průměru;
  -- další až po dalších 14 dnech.
  if not exists (
    select 1 from public.user_achievements ua join public.nights x on x.id = ua.night_id
    where ua.user_id = n.user_id and ua.code = 'swiss_watch' and x.night_date > n.night_date - 14
  ) then
    with last14 as (
      select private.minutes_from_noon(sleep_start, v_tz) as sm
      from public.nights
      where user_id = n.user_id and night_date > n.night_date - 14 and night_date <= n.night_date
    )
    select count(*) = 14 and max(abs(sm - (select avg(sm) from last14))) <= 15
      into v_ok from last14;
    if v_ok then perform private.award(n.user_id, 'swiss_watch', n.id); end if;
  end if;
end;
$$;

-- Tagové achievementy hned při uložení tagu.
create function private.on_night_tag()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.tag = 'alcohol' then
    perform private.award_tag_achievements(new.night_id);
  end if;
  return null;
end;
$$;
create trigger night_tags_award after insert on public.night_tags
  for each row execute function private.on_night_tag();

-- Dvojí život: o víkendu usnutí o 3+ h později než v týdnu (minulý týden).
create function private.award_double_life(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_tz     text;
  v_mon    date;
  v_we_avg numeric; v_we_cnt int;
  v_wd_avg numeric; v_wd_cnt int;
  v_night  uuid;
begin
  select timezone into v_tz from public.profiles where id = p_user;
  v_mon := date_trunc('week', (now() at time zone v_tz)::date)::date - 7;   -- pondělí minulého týdne
  -- víkend = noci pá→so a so→ne (night_date so, ne); týden = po→út … čt→pá
  select avg(sm) filter (where night_date in (v_mon + 5, v_mon + 6)),
         count(*) filter (where night_date in (v_mon + 5, v_mon + 6)),
         avg(sm) filter (where night_date between v_mon + 1 and v_mon + 4),
         count(*) filter (where night_date between v_mon + 1 and v_mon + 4)
    into v_we_avg, v_we_cnt, v_wd_avg, v_wd_cnt
  from (select night_date, private.minutes_from_noon(sleep_start, v_tz) as sm
        from public.nights where user_id = p_user and night_date between v_mon + 1 and v_mon + 6) x;

  if v_we_cnt >= 1 and v_wd_cnt >= 2 and v_we_avg - v_wd_avg >= 180 then
    select id into v_night from public.nights
    where user_id = p_user and night_date in (v_mon + 5, v_mon + 6)
    order by night_date desc limit 1;
    perform private.award(p_user, 'double_life', v_night);
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Série
-- Dobrá noc = aspoň 6 h a usnutí ±30 min od průměru předchozích 14 nocí
-- (při < 3 nocích historie stačí délka). Streak freeze: první špatná /
-- chybějící noc v týdnu sérii nepřeruší, ale nepřičte se.
-- Přepočítává se celá historie jednoho uživatele (ms), aby sedělo i
-- zpětné nahrávání.
-- ---------------------------------------------------------------------
create function private.recompute_streak(p_user uuid)
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
      v_cur := v_cur + 1;
      v_last_good := r.day;
      -- milníky jen za poslední týden (ať zpětný přepočet neudílí staré)
      if v_cur in (7, 30, 100) and r.day >= v_asof - 7 then
        if private.award(p_user, 'streak_' || v_cur, r.night_id) and v_cur in (30, 100) then
          update public.profiles set invites_available = invites_available + 1 where id = p_user;
        end if;
      end if;
    elsif v_freeze is distinct from date_trunc('week', r.day)::date then
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

-- Volá ingest-sleep (service role) po uložení noci.
create function public.after_night_ingest(p_night uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid;
  v_res  jsonb;
begin
  select user_id into v_user from public.nights where id = p_night;
  if not found then return null; end if;
  perform private.award_night_achievements(p_night);
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

-- ---------------------------------------------------------------------
-- Uzavření výzvy (poslední den ve 14:00 v pásmu zakladatele)
-- ---------------------------------------------------------------------
create function private.finalize_challenge(p_challenge uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  c          public.challenges;
  v_top      numeric;
  v_ntop     int;
  v_second   numeric;
  v_winner   uuid;
  v_wins     int;
  v_souls    int;
  v_new      int;
  v_run      int := 0;
  v_nemesis  uuid;
  r          record;
begin
  select * into c from public.challenges where id = p_challenge and status = 'active' for update skip locked;
  if not found then return; end if;

  -- 1) skóre z nocí, které se do výzvy nepropsaly, a nuly za chybějící noci
  insert into public.challenge_day_scores (challenge_id, user_id, day, score, night_id)
  select c.id, p.user_id, n.night_date, n.score, n.id
  from public.challenge_participants p
  join public.nights n on n.user_id = p.user_id
  where p.challenge_id = c.id and p.status = 'accepted' and n.score is not null
    and n.night_date between c.start_date and c.end_date
  on conflict do nothing;

  insert into public.challenge_day_scores (challenge_id, user_id, day, score)
  select c.id, p.user_id, d::date, 0
  from public.challenge_participants p
  cross join generate_series(c.start_date, c.end_date, interval '1 day') d
  where p.challenge_id = c.id and p.status = 'accepted'
  on conflict do nothing;

  perform private.award(x.user_id, 'forgot_watch', null, c.id)
  from (select distinct user_id from public.challenge_day_scores
        where challenge_id = c.id and night_id is null) x;

  -- 2) průměry a vyhrané dny (den vyhrává jen jasně nejvyšší skóre)
  update public.challenge_participants p
  set final_avg = s.avg_score, days_won = s.won
  from (
    select d.user_id,
           round(avg(d.score), 2) as avg_score,
           count(*) filter (where d.score > coalesce(
             (select max(o.score) from public.challenge_day_scores o
              where o.challenge_id = d.challenge_id and o.day = d.day and o.user_id <> d.user_id), -1)) as won
    from public.challenge_day_scores d
    where d.challenge_id = c.id
    group by d.user_id
  ) s
  where p.challenge_id = c.id and p.user_id = s.user_id and p.status = 'accepted';

  -- 3) výsledky
  if c.type = 'team_goal' then
    update public.challenge_participants
    set result = case when (select avg(score) from public.challenge_day_scores where challenge_id = c.id)
                           >= c.target_score then 'win'::public.challenge_result
                      else 'loss'::public.challenge_result end
    where challenge_id = c.id and status = 'accepted';
  else
    select max(final_avg) into v_top
    from public.challenge_participants where challenge_id = c.id and status = 'accepted';
    select count(*) into v_ntop
    from public.challenge_participants where challenge_id = c.id and status = 'accepted' and final_avg = v_top;

    update public.challenge_participants
    set result = case when final_avg < v_top then 'loss'::public.challenge_result
                      when v_ntop = 1 then 'win'::public.challenge_result
                      else 'draw'::public.challenge_result end
    where challenge_id = c.id and status = 'accepted';
  end if;

  update public.challenges set status = 'finished', finalized_at = now() where id = c.id;
  insert into public.posts (kind, challenge_id) values ('challenge_result', c.id) on conflict do nothing;

  -- 4) jasný vítěz (duel / všichni proti všem): dluhy, pozvánka, achievementy
  if c.type = 'team_goal' or v_ntop <> 1 then return; end if;

  select user_id into v_winner from public.challenge_participants where challenge_id = c.id and result = 'win';

  if c.stake is not null then
    insert into public.debts (challenge_id, debtor_id, creditor_id, stake)
    select c.id, user_id, v_winner, c.stake
    from public.challenge_participants where challenge_id = c.id and result = 'loss';
  end if;

  update public.profiles set invites_available = invites_available + 1 where id = v_winner;

  select count(*) into v_wins
  from public.challenge_participants cp join public.challenges x on x.id = cp.challenge_id
  where cp.user_id = v_winner and cp.result = 'win' and x.status = 'finished' and x.type <> 'team_goal';
  if v_wins = 1 then perform private.award(v_winner, 'first_soul', null, c.id); end if;

  select count(*) into v_souls from public.souls where winner_id = v_winner;
  select count(*) into v_new from public.challenge_participants where challenge_id = c.id and result = 'loss';
  if v_souls / 10 > (v_souls - v_new) / 10 then
    perform private.award(v_winner, 'collector', null, c.id);
  end if;

  for r in
    select cp.result from public.challenge_participants cp join public.challenges x on x.id = cp.challenge_id
    where cp.user_id = v_winner and cp.status = 'accepted' and x.status = 'finished' and x.type <> 'team_goal'
    order by x.end_date desc, x.finalized_at desc
  loop
    exit when r.result <> 'win';
    v_run := v_run + 1;
  end loop;
  if v_run > 0 and v_run % 5 = 0 then perform private.award(v_winner, 'undefeated', null, c.id); end if;

  -- Odplata: porazil jsi toho, kdo tě naposledy porazil
  select w.user_id into v_nemesis
  from public.challenge_participants me
  join public.challenges x on x.id = me.challenge_id
  join public.challenge_participants w on w.challenge_id = x.id and w.result = 'win'
  where me.user_id = v_winner and me.result = 'loss' and x.status = 'finished'
    and x.type <> 'team_goal' and x.id <> c.id
  order by x.end_date desc, x.finalized_at desc
  limit 1;
  if v_nemesis is not null and exists (
    select 1 from public.challenge_participants
    where challenge_id = c.id and user_id = v_nemesis and result = 'loss'
  ) then
    perform private.award(v_winner, 'revenge', null, c.id);
  end if;

  select max(final_avg) into v_second from public.challenge_participants where challenge_id = c.id and result = 'loss';
  if v_top - v_second < 1 then perform private.award(v_winner, 'by_a_hair', null, c.id); end if;
end;
$$;

create function private.finalize_due_challenges()
returns int language plpgsql security definer set search_path = '' as $$
declare
  r record;
  n int := 0;
begin
  for r in
    select c.id from public.challenges c join public.profiles p on p.id = c.creator_id
    where c.status = 'active' and now() >= ((c.end_date + time '14:00') at time zone p.timezone)
  loop
    perform private.finalize_challenge(r.id);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------
-- Hodinová úloha (pg_cron)
-- ---------------------------------------------------------------------
create function private.hourly_jobs()
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.finalize_due_challenges();

  -- Díry v sériích: jednou denně po 14:00 místního času, jen lidé
  -- s rozjetou sérií, kterým se dnes po 14:00 ještě nepřepočítala.
  perform private.recompute_streak(s.user_id)
  from public.user_stats s join public.profiles p on p.id = s.user_id
  where s.current_streak > 0
    and (now() at time zone p.timezone)::time >= '14:00'
    and s.updated_at < (((now() at time zone p.timezone)::date + time '14:00') at time zone p.timezone);

  -- Dvojí život: v pondělí v 10:00 místního času
  perform private.award_double_life(p.id)
  from public.profiles p
  where extract(isodow from now() at time zone p.timezone) = 1
    and extract(hour from now() at time zone p.timezone) = 10;
end;
$$;

-- ---------------------------------------------------------------------
-- Práva
-- ---------------------------------------------------------------------
revoke execute on function public.after_night_ingest(uuid) from public, anon, authenticated;
grant execute on function public.after_night_ingest(uuid) to service_role;

revoke execute on function
  private.minutes_from_noon(timestamptz, text),
  private.award(uuid, text, uuid, uuid),
  private.award_tag_achievements(uuid),
  private.award_night_achievements(uuid),
  private.on_night_tag(),
  private.award_double_life(uuid),
  private.recompute_streak(uuid),
  private.finalize_challenge(uuid),
  private.finalize_due_challenges(),
  private.hourly_jobs()
from public, anon, authenticated;
