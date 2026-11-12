-- #34: Týdenní freeze se spotřeboval i na špatnou noc při nulové sérii
-- (pak pozdější špatná noc v témž týdnu rozjetou sérii přerušila).
-- Freeze se teď použije jen když je co chránit (série > 0). Jinak beze změny.

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
