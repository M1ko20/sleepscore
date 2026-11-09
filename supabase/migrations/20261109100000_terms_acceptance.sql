-- =====================================================================
-- Souhlas s podmínkami a zásadami (App Store 1.2 a 5.1.1, issue #20).
--
-- Aktuální verze = datum účinnosti podmínek na webu (site/terms.html).
-- Při změně podmínek: nová migrace s novou `private.terms_version()` →
-- appka po spuštění všem znovu ukáže souhlas (my_terms_status).
--
-- Souhlas vzniká ještě před profilem (onboarding), proto FK na auth.users.
-- redeem_invite bez souhlasu s aktuální verzí profil nezaloží.
-- =====================================================================

create function private.terms_version()
returns text language sql immutable set search_path = '' as $$
  select '2026-11-06';
$$;

create table public.terms_acceptances (
  user_id     uuid not null references auth.users (id) on delete cascade,
  version     text not null,
  accepted_at timestamptz not null default now(),
  primary key (user_id, version)
);

alter table public.terms_acceptances enable row level security;
create policy terms_acceptances_select on public.terms_acceptances for select to authenticated
  using (user_id = auth.uid());
revoke insert, update, delete on public.terms_acceptances from authenticated, anon;

-- Souhlas s aktuální verzí. Idempotentní (opakovaný souhlas nemění čas prvního).
create function public.accept_terms()
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  insert into public.terms_acceptances (user_id, version)
  values (auth.uid(), private.terms_version())
  on conflict do nothing;
  return public.my_terms_status();
end;
$$;

-- {"version": "2026-11-06", "accepted": true, "accepted_at": "…"}
create function public.my_terms_status()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'version', private.terms_version(),
    'accepted', ta.accepted_at is not null,
    'accepted_at', ta.accepted_at)
  from (select 1) _
  left join public.terms_acceptances ta
    on ta.user_id = auth.uid() and ta.version = private.terms_version();
$$;

revoke execute on function public.accept_terms(), public.my_terms_status() from public, anon;
grant execute on function public.accept_terms(), public.my_terms_status() to authenticated;

-- ---------------------------------------------------------------------
-- redeem_invite: bez souhlasu s aktuálními podmínkami profil nevznikne.
-- (Tělo jinak beze změny proti init.)
-- ---------------------------------------------------------------------
create or replace function public.redeem_invite(p_code text, p_username text, p_display_name text)
returns public.profiles
language plpgsql security definer set search_path = '' as $$
declare
  v_invite  public.invites;
  v_profile public.profiles;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if exists (select 1 from public.profiles where id = auth.uid()) then
    raise exception 'profile already exists';
  end if;
  if not exists (select 1 from public.terms_acceptances
                 where user_id = auth.uid() and version = private.terms_version()) then
    raise exception 'terms not accepted';
  end if;

  select * into v_invite from public.invites
  where code = upper(p_code) and redeemed_by is null
  for update;
  if not found then raise exception 'invalid or used invite'; end if;

  insert into public.profiles (id, username, display_name, invited_by)
  values (auth.uid(), lower(p_username), p_display_name, v_invite.inviter_id)
  returning * into v_profile;

  update public.invites set redeemed_by = auth.uid(), redeemed_at = now()
  where code = v_invite.code;

  insert into public.friendships (user_a, user_b, requested_by, status, accepted_at)
  values (least(auth.uid(), v_invite.inviter_id), greatest(auth.uid(), v_invite.inviter_id),
          v_invite.inviter_id, 'accepted', now());

  insert into public.user_stats (user_id) values (auth.uid());
  return v_profile;
end;
$$;

-- ---------------------------------------------------------------------
-- Export (GDPR): + souhlasy s podmínkami. Jinak beze změny proti 20261107140000.
-- ---------------------------------------------------------------------
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
                               from public.notifications n where n.user_id = auth.uid()), '[]'::jsonb),
    -- úplné nastavení (bez uloženého řádku = výchozí) + kdy se naposledy měnilo
    'notification_prefs', private.notification_prefs_default()
                          || coalesce((select np.prefs from public.notification_prefs np where np.user_id = auth.uid()), '{}'::jsonb)
                          || jsonb_build_object('updated_at',
                               (select np.updated_at from public.notification_prefs np where np.user_id = auth.uid())),
    'terms_acceptances', coalesce((select jsonb_agg(jsonb_build_object('version', ta.version, 'accepted_at', ta.accepted_at)
                                                    order by ta.accepted_at)
                                   from public.terms_acceptances ta where ta.user_id = auth.uid()), '[]'::jsonb)
  );
$$;
revoke execute on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;

-- Stávající uživatelé (beta) nemají záznam → appka jim souhlas ukáže po spuštění.
