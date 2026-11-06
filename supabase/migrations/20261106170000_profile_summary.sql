-- Profil jedním callem (šetří requesty na Free tarifu).
-- security invoker: všechno jde přes RLS a security_invoker pohledy,
-- takže u cizího (ne-přítele) se vrátí jen veřejné minimum (null / prázdné).
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
      where f.user_a = least(auth.uid(), p_user) and f.user_b = greatest(auth.uid(), p_user))
  );
$$;

revoke execute on function public.profile_summary(uuid) from public, anon;
grant execute on function public.profile_summary(uuid) to authenticated;
