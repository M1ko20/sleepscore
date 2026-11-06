-- Zjištění z tagů a týdenní recap. Vše na požádání (žádný cron, žádná Edge Function)
-- a security invoker → přes RLS.

-- Minuty od poledne místního času (usnutí 23:30 = 690, 0:30 = 750) → průměr přes půlnoc dává smysl.
create or replace function public.minutes_since_noon(p_ts timestamptz, p_tz text)
returns int language sql immutable set search_path = '' as $$
  select ((extract(epoch from (p_ts at time zone p_tz)::time) / 60)::int - 720 + 1440) % 1440;
$$;

-- Pro každý tag: noci s tagem vs. bez něj za 90 dní (min. 3 + 3).
-- Appka z rozdílů vybere nejsilnější a složí větu („S alkoholem máš o 38 % méně deep…“).
create or replace function public.tag_insights(p_user uuid)
returns jsonb
language sql stable security invoker set search_path = '' as $$
  with base as (
    select n.id, n.score, n.total_sleep_min,
           case when n.core_min + n.deep_min + n.rem_min > 0
                then n.deep_min::numeric / nullif(n.total_sleep_min, 0) end as deep_share,
           public.minutes_since_noon(n.sleep_start, p.timezone) as onset
    from public.nights n
    join public.profiles p on p.id = n.user_id
    where n.user_id = p_user and n.night_date > current_date - 90 and n.score is not null
  ),
  marked as (
    select t.slug, t.label, b.*,
           exists (select 1 from public.night_tags x where x.night_id = b.id and x.tag = t.slug) as w
    from public.tags t cross join base b
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'tag', slug, 'label', label,
           'n_with', n_with, 'n_without', n_without,
           'score_with', score_with, 'score_without', score_without,
           'deep_with', deep_with, 'deep_without', deep_without,
           'onset_with', onset_with, 'onset_without', onset_without,
           'sleep_with', sleep_with, 'sleep_without', sleep_without)
         order by abs(score_with - score_without) desc), '[]'::jsonb)
  from (
    select slug, label,
           count(*) filter (where w) as n_with,
           count(*) filter (where not w) as n_without,
           round(avg(score) filter (where w), 1) as score_with,
           round(avg(score) filter (where not w), 1) as score_without,
           round(avg(deep_share) filter (where w), 3) as deep_with,
           round(avg(deep_share) filter (where not w), 3) as deep_without,
           round(avg(onset) filter (where w)) as onset_with,
           round(avg(onset) filter (where not w)) as onset_without,
           round(avg(total_sleep_min) filter (where w)) as sleep_with,
           round(avg(total_sleep_min) filter (where not w)) as sleep_without
    from marked
    group by slug, label
    having count(*) filter (where w) >= 3 and count(*) filter (where not w) >= 3
  ) s;
$$;

-- Týdenní recap volajícího. Bez parametru = minulý celý týden (po–ne podle data noci).
create or replace function public.weekly_recap(p_week_start date default null)
returns jsonb
language sql stable security invoker set search_path = '' as $$
  with me as (
    select p.id, p.timezone,
           coalesce(p_week_start,
                    date_trunc('week', (now() at time zone p.timezone))::date - 7) as ws
    from public.profiles p where p.id = auth.uid()
  ),
  week as (
    select n.night_date, n.score, n.total_sleep_min
    from public.nights n, me
    where n.user_id = me.id and n.night_date between me.ws and me.ws + 6 and n.score is not null
  )
  select jsonb_build_object(
    'week_start', me.ws,
    'week_end', me.ws + 6,
    'nights', (select count(*) from week),
    'avg_score', (select round(avg(score), 1) from week),
    'avg_sleep_min', (select round(avg(total_sleep_min)) from week),
    'prev_avg_score', (select round(avg(n.score), 1) from public.nights n
                       where n.user_id = me.id and n.score is not null
                         and n.night_date between me.ws - 7 and me.ws - 1),
    'best', (select jsonb_build_object('date', night_date, 'score', score)
             from week order by score desc, night_date limit 1),
    'worst', (select jsonb_build_object('date', night_date, 'score', score)
              from week order by score, night_date limit 1),
    'streak', (select jsonb_build_object('current', s.current_streak, 'best', s.best_streak)
               from public.user_stats s where s.user_id = me.id),
    'achievements', (select count(*) from public.user_achievements a
                     where a.user_id = me.id
                       and (a.earned_at at time zone me.timezone)::date between me.ws and me.ws + 6)
  )
  from me;
$$;

create or replace function public.profile_summary(p_user uuid)
returns jsonb
language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'profile', (
      select jsonb_build_object('id', p.id, 'username', p.username, 'display_name', p.display_name,
                                'avatar_path', p.avatar_path, 'timezone', p.timezone)
      from public.profiles p where p.id = p_user),
    'mma', (
      select jsonb_build_object('wins', coalesce(m.wins, 0), 'losses', coalesce(m.losses, 0),
                                'draws', coalesce(m.draws, 0))
      from (select 1) x left join public.mma_records m on m.user_id = p_user),
    'streak', (
      select jsonb_build_object('current', s.current_streak, 'best', s.best_streak)
      from public.user_stats s where s.user_id = p_user),
    'avg30', (
      select jsonb_build_object('score', round(avg(n.score), 1),
                                'sleep_min', round(avg(n.total_sleep_min)),
                                'nights', count(*))
      from public.nights n
      where n.user_id = p_user and n.night_date > current_date - 30 and n.score is not null
      having count(*) > 0),
    'souls', coalesce((
      select jsonb_agg(jsonb_build_object(
               'loser', jsonb_build_object('id', p.id, 'username', p.username,
                                           'display_name', p.display_name, 'avatar_path', p.avatar_path,
                                           'timezone', p.timezone),
               'count', g.cnt, 'last_date', g.last_date)
             order by g.last_date desc)
      from (select loser_id, count(*) as cnt, max(end_date) as last_date
            from public.souls where winner_id = p_user group by loser_id) g
      join public.profiles p on p.id = g.loser_id), '[]'::jsonb),
    'achievements', coalesce((
      select jsonb_agg(jsonb_build_object('code', code, 'count', cnt))
      from (select code, count(*) as cnt from public.user_achievements
            where user_id = p_user group by code) a), '[]'::jsonb),
    -- Vzájemná bilance z pohledu volajícího proti p_user.
    'h2h', (
      select jsonb_build_object('wins', h.wins, 'losses', h.losses, 'draws', h.draws)
      from public.head_to_head h
      where h.user_id = auth.uid() and h.opponent_id = p_user and p_user <> auth.uid()),
    'friendship', (
      select jsonb_build_object('status', f.status, 'requested_by', f.requested_by)
      from public.friendships f
      where f.user_a = least(auth.uid(), p_user) and f.user_b = greatest(auth.uid(), p_user)),
    -- Zjištění z tagů jen na vlastním profilu (osobní, a u cizích by se zbytečně počítala).
    'insights', case when p_user = auth.uid() then public.tag_insights(p_user) end,
    'nights_90', case when p_user = auth.uid() then (
      select count(*) from public.nights n
      where n.user_id = p_user and n.night_date > current_date - 90 and n.score is not null) end
  );
$$;


revoke execute on function public.tag_insights(uuid), public.weekly_recap(date) from public, anon;
grant execute on function public.tag_insights(uuid), public.weekly_recap(date) to authenticated;
revoke execute on function public.minutes_since_noon(timestamptz, text) from public, anon;
grant execute on function public.minutes_since_noon(timestamptz, text) to authenticated;
