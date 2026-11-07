-- Export dat (GDPR čl. 15/20) doplněný o bloky, podaná hlášení a notifikace.
-- Hlášení klient přes RLS nevidí, proto je funkce nově security definer; každý dotaz
-- je omezený na auth.uid(). U hlášení se neexportuje snapshot (obsah jiných lidí)
-- ani interní poznámka k vyřízení.
create or replace function public.export_my_data()
returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'exported_at', now(),
    'profile', (select to_jsonb(p) from public.profiles p where p.id = auth.uid()),
    'stats', (select to_jsonb(s) from public.user_stats s where s.user_id = auth.uid()),
    'nights', coalesce((select jsonb_agg(to_jsonb(n) || jsonb_build_object(
                          'raw', (select to_jsonb(r) - 'night_id' from public.night_raw r where r.night_id = n.id),
                          'tags', (select coalesce(jsonb_agg(t.tag), '[]'::jsonb) from public.night_tags t where t.night_id = n.id))
                        order by n.night_date)
                        from public.nights n where n.user_id = auth.uid()), '[]'::jsonb),
    'posts', coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at)
                       from public.posts p where p.user_id = auth.uid()), '[]'::jsonb),
    'comments', coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at)
                          from public.comments c where c.user_id = auth.uid()), '[]'::jsonb),
    'reactions', coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at)
                           from public.reactions r where r.user_id = auth.uid()), '[]'::jsonb),
    'friendships', coalesce((select jsonb_agg(to_jsonb(f))
                             from public.friendships f where auth.uid() in (f.user_a, f.user_b)), '[]'::jsonb),
    'challenges', coalesce((select jsonb_agg(to_jsonb(c) || jsonb_build_object('me', to_jsonb(cp) - 'challenge_id'))
                            from public.challenge_participants cp join public.challenges c on c.id = cp.challenge_id
                            where cp.user_id = auth.uid()), '[]'::jsonb),
    'challenge_day_scores', coalesce((select jsonb_agg(to_jsonb(d) order by d.day)
                                      from public.challenge_day_scores d where d.user_id = auth.uid()), '[]'::jsonb),
    'debts', coalesce((select jsonb_agg(to_jsonb(d))
                       from public.debts d where auth.uid() in (d.debtor_id, d.creditor_id)), '[]'::jsonb),
    'achievements', coalesce((select jsonb_agg(to_jsonb(a) order by a.earned_at)
                              from public.user_achievements a where a.user_id = auth.uid()), '[]'::jsonb),
    'invites', coalesce((select jsonb_agg(to_jsonb(i))
                         from public.invites i where i.inviter_id = auth.uid()), '[]'::jsonb),
    'blocks', coalesce((select jsonb_agg(jsonb_build_object('blocked_id', b.blocked_id, 'created_at', b.created_at) order by b.created_at)
                        from public.blocks b where b.blocker_id = auth.uid()), '[]'::jsonb),
    'reports_filed', coalesce((select jsonb_agg(jsonb_build_object(
                               'target_kind', r.target_kind, 'target_id', r.target_id, 'reason', r.reason,
                               'note', r.note, 'status', r.status, 'created_at', r.created_at, 'resolved_at', r.resolved_at)
                               order by r.created_at)
                               from public.reports r where r.reporter_id = auth.uid()), '[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at)
                               from public.notifications n where n.user_id = auth.uid()), '[]'::jsonb)
  );
$$;
revoke execute on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;
