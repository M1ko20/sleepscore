-- #36 drobnosti z review:
-- 1) Upozornění „předbíhá tě“ počítalo „dnes“ v pásmu profilu zakladatele
--    (po jeho smazání Praha) místo v pásmu výzvy.
-- 2) minutes_since_noon byla `immutable`, převod pásma je jen `stable`.

create or replace function private.on_day_score_notify()
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
  v_tz := c.timezone;
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

alter function public.minutes_since_noon(timestamptz, text) stable;
