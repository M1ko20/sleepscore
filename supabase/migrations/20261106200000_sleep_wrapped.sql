-- Sleep Wrapped: rok volajícího jedním callem (na požádání, security invoker → RLS).
-- Noci podle night_date, výzvy podle end_date v daném roce.
create or replace function public.sleep_wrapped(p_year int default null)
returns jsonb
language sql stable security invoker set search_path = '' as $$
  with me as (
    select p.id, p.timezone,
           coalesce(p_year,
                    -- v lednu ještě uplynulý rok, jinak letošní
                    case when extract(month from now() at time zone p.timezone) = 1
                         then extract(year from now() at time zone p.timezone)::int - 1
                         else extract(year from now() at time zone p.timezone)::int end) as y
    from public.profiles p where p.id = auth.uid()
  ),
  n as (
    select x.* from public.nights x, me
    where x.user_id = me.id and x.score is not null
      and x.night_date between make_date(me.y, 1, 1) and make_date(me.y, 12, 31)
  ),
  ch as (
    select c.id, c.type, cp.result
    from public.challenges c
    join public.challenge_participants cp on cp.challenge_id = c.id
    cross join me
    where cp.user_id = me.id and c.status = 'finished'
      and c.end_date between make_date(me.y, 1, 1) and make_date(me.y, 12, 31)
  ),
  souls_y as (
    select s.* from public.souls s, me
    where s.end_date between make_date(me.y, 1, 1) and make_date(me.y, 12, 31)
  ),
  lite as (
    select p.id, jsonb_build_object('id', p.id, 'username', p.username, 'display_name', p.display_name,
                                    'avatar_path', p.avatar_path, 'timezone', p.timezone) as j
    from public.profiles p
  )
  select jsonb_build_object(
    'year', me.y,
    'nights', (select count(*) from n),
    'total_sleep_min', (select coalesce(sum(total_sleep_min), 0) from n),
    'deep_min', (select coalesce(sum(deep_min), 0) from n),
    'avg_score', (select round(avg(score), 1) from n),
    'avg_onset', (select round(avg(public.minutes_since_noon(sleep_start, me.timezone))) from n),
    'best_night', (select jsonb_build_object('date', night_date, 'score', score)
                   from n order by score desc, night_date limit 1),
    'best_month', (select jsonb_build_object('month', m, 'avg', a) from (
                     select extract(month from night_date)::int as m, round(avg(score), 1) as a
                     from n group by 1 having count(*) >= 5 order by 2 desc limit 1) bm),
    'best_streak', (select s.best_streak from public.user_stats s where s.user_id = me.id),
    'top_tags', coalesce((select jsonb_agg(jsonb_build_object('tag', t.slug, 'label', t.label, 'count', c) order by c desc)
                          from (select nt.tag, count(*) as c from public.night_tags nt join n on n.id = nt.night_id
                                group by nt.tag order by 2 desc limit 3) x
                          join public.tags t on t.slug = x.tag), '[]'::jsonb),
    'record', (select jsonb_build_object(
                 'wins', count(*) filter (where result = 'win'),
                 'losses', count(*) filter (where result = 'loss'),
                 'draws', count(*) filter (where result = 'draw')) from ch),
    'challenges', (select count(*) from ch),
    'souls', (select count(*) from souls_y, me where winner_id = me.id),
    -- Koho jsem porazil nejčastěji / kdo mě nejčastěji
    'victim', (select jsonb_build_object('profile', l.j, 'count', c) from (
                 select loser_id, count(*) as c from souls_y, me where winner_id = me.id
                 group by loser_id order by 2 desc limit 1) v join lite l on l.id = v.loser_id),
    'nemesis', (select jsonb_build_object('profile', l.j, 'count', c) from (
                  select winner_id, count(*) as c from souls_y, me where loser_id = me.id
                  group by winner_id order by 2 desc limit 1) v join lite l on l.id = v.winner_id),
    'achievements', (select count(*) from public.user_achievements a
                     where a.user_id = me.id
                       and extract(year from a.earned_at at time zone me.timezone) = me.y),
    'top_achievement', (select jsonb_build_object('code', code, 'count', c) from (
                          select a.code, count(*) as c from public.user_achievements a
                          where a.user_id = me.id
                            and extract(year from a.earned_at at time zone me.timezone) = me.y
                          group by a.code order by 2 desc, 1 limit 1) ta),
    'reactions', (select count(*) from public.reactions r join public.posts p on p.id = r.post_id
                  join n on n.id = p.night_id),
    'top_reaction', (select r.kind from public.reactions r join public.posts p on p.id = r.post_id
                     join n on n.id = p.night_id group by r.kind order by count(*) desc limit 1),
    'comments', (select count(*) from public.comments cm join public.posts p on p.id = cm.post_id
                 join n on n.id = p.night_id cross join me where cm.user_id <> me.id)
  )
  from me;
$$;

revoke execute on function public.sleep_wrapped(int) from public, anon;
grant execute on function public.sleep_wrapped(int) to authenticated;
