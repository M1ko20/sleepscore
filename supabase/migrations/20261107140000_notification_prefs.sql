-- =====================================================================
-- Nastavení notifikací: přepínače po kategoriích a noční klid. Issue #11.
--
-- Platí jen pro pushe (#10). Zvoneček v appce ukazuje vše.
--
-- Uložené ve vlastní tabulce, ne v `profiles`: profily čte každý člen
-- (hledání přátel), nastavení má vidět jen majitel.
-- Chybějící řádek = výchozí stav (vše zapnuto, noční klid zapnutý).
--
-- Klíče = `notifications.category` + `quiet_hours`:
--   reactions, comments, friends, challenges, achievements, morning, recap
--   quiet_hours – noční klid 22:00–8:00 v `profiles.timezone`: push počká do 8:00.
-- =====================================================================

create function private.notification_prefs_default()
returns jsonb language sql immutable set search_path = '' as $$
  select '{"reactions": true, "comments": true, "friends": true, "challenges": true,
           "achievements": true, "morning": true, "recap": true, "quiet_hours": true}'::jsonb;
$$;

-- Objekt jen se známými klíči a hodnotami true/false (může být neúplný).
create function private.notification_prefs_valid(p jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select jsonb_typeof(p) = 'object'
     and not exists (
       select 1 from jsonb_each(p) e
       where not (private.notification_prefs_default() ? e.key)
          or jsonb_typeof(e.value) <> 'boolean');
$$;

create table public.notification_prefs (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  prefs      jsonb not null default private.notification_prefs_default(),
  updated_at timestamptz not null default now(),
  -- uložené je vždy úplné (všechny klíče)
  constraint notification_prefs_valid check (
    private.notification_prefs_valid(prefs)
    and prefs ?& array['reactions', 'comments', 'friends', 'challenges',
                       'achievements', 'morning', 'recap', 'quiet_hours'])
);

alter table public.notification_prefs enable row level security;
-- Číst jen svoje. Zápis jen přes set_notification_prefs (klient nemá insert/update).
create policy notification_prefs_select on public.notification_prefs for select to authenticated
  using (user_id = auth.uid());
revoke insert, update, delete on public.notification_prefs from authenticated, anon;

-- ---------------------------------------------------------------------
-- RPC pro appku
-- ---------------------------------------------------------------------

-- Moje nastavení (úplné, s výchozími hodnotami).
create function public.my_notification_prefs()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.notification_prefs_default()
         || coalesce((select np.prefs from public.notification_prefs np where np.user_id = auth.uid()), '{}'::jsonb);
$$;
revoke execute on function public.my_notification_prefs() from public, anon;
grant execute on function public.my_notification_prefs() to authenticated;

-- Uloží změnu. Stačí poslat měněné klíče: {"reactions": false}. Vrací úplné nastavení.
create function public.set_notification_prefs(p_prefs jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
  v_prefs jsonb;
begin
  if v_me is null or not private.is_member() then raise exception 'not a member'; end if;
  if p_prefs is null or not private.notification_prefs_valid(p_prefs) then
    raise exception 'invalid notification prefs';
  end if;
  insert into public.notification_prefs as np (user_id, prefs)
  values (v_me, private.notification_prefs_default() || p_prefs)
  on conflict (user_id) do update
    set prefs = private.notification_prefs_default() || np.prefs || p_prefs,
        updated_at = now()
  returning np.prefs into v_prefs;
  return v_prefs;
end;
$$;
revoke execute on function public.set_notification_prefs(jsonb) from public, anon;
grant execute on function public.set_notification_prefs(jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- Pro odesílač pushů (#10): co s notifikací teď udělat.
--   'send' – pushnout teď
--   'hold' – noční klid, nechat ve frontě (v 8:00 místního času vyjde 'send')
--   'skip' – kategorie vypnutá, nepushovat (odesílač nastaví pushed_at, ať zmizí z fronty)
-- Neplatné časové pásmo v profilu → Europe/Prague (výchozí v profiles).
-- Jen pro server (service role / cron), klient ji volat nemůže.
-- ---------------------------------------------------------------------
create function private.push_decision(p_user uuid, p_category text, p_now timestamptz default now())
returns text language plpgsql stable set search_path = '' as $$
declare
  v_prefs jsonb;
  v_tz text;
  v_local time;
begin
  select private.notification_prefs_default() || coalesce(np.prefs, '{}'::jsonb), p.timezone
    into v_prefs, v_tz
  from public.profiles p
  left join public.notification_prefs np on np.user_id = p.id
  where p.id = p_user;
  if not found then return 'skip'; end if;   -- profil neexistuje

  if coalesce((v_prefs ->> p_category)::boolean, true) is false then return 'skip'; end if;

  if (v_prefs ->> 'quiet_hours')::boolean then
    begin
      v_local := (p_now at time zone v_tz)::time;
    exception when others then
      v_local := (p_now at time zone 'Europe/Prague')::time;
    end;
    if v_local >= time '22:00' or v_local < time '08:00' then return 'hold'; end if;
  end if;
  return 'send';
end;
$$;

-- Varianta přímo pro řádek z fronty: private.push_decision(n) / private.push_decision(n, p_now)
create function private.push_decision(n public.notifications, p_now timestamptz default now())
returns text language sql stable set search_path = '' as $$
  select private.push_decision(n.user_id, n.category, p_now);
$$;

revoke execute on function private.push_decision(uuid, text, timestamptz) from public, anon, authenticated;
revoke execute on function private.push_decision(public.notifications, timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Export dat (GDPR): navíc nastavení notifikací. Jinak beze změny
-- proti 20261107120000_export_moderation_notifications.sql.
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
                               (select np.updated_at from public.notification_prefs np where np.user_id = auth.uid()))
  );
$$;
revoke execute on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;
