-- =====================================================================
-- Push notifikace přes APNs (#10).
--
-- Tok:
--   pg_cron každou minutu ─▶ private.push_tick()
--     - uklidí frontu (vypnutá kategorie, bez tokenu, starší než den),
--     - jen když je co poslat a je nastavená URL, zavolá přes pg_net
--       Edge Function `send-push` (prázdná fronta = 0 callů, jinak max 1/min).
--   send-push ─▶ claim_push_batch()   (zamkne a označí pushed_at, vrátí dávku po uživatelích)
--             ─▶ APNs (HTTP/2, JWT ES256 – Postgres podepsat neumí, proto Edge Function)
--             ─▶ finish_push_batch()  (smaže neplatné tokeny, uloží JWT do cache)
--
-- Zapnutí (až bude APNs klíč, mimo git):
--   supabase secrets set PUSH_SECRET=<náhodný> (+ APNs klíč, viz send-push/index.ts)
--   insert into private.app_config values
--     ('push_function_url', 'https://<projekt>.supabase.co/functions/v1/send-push'),
--     ('push_secret', '<stejný náhodný>');
-- Bez `push_function_url` se nic neposílá a fronta se jen uklízí.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tokeny: prostředí APNs (Debug build = sandbox, TestFlight/App Store = production).
-- Registrace přes RPC: token se může přestěhovat k jinému účtu (odhlášení a přihlášení
-- na stejném telefonu) a přímý upsert by cizí řádek kvůli RLS nepřepsal.
-- ---------------------------------------------------------------------
alter table public.push_tokens
  add column env text not null default 'production' check (env in ('production', 'sandbox'));
create index push_tokens_user_idx on public.push_tokens (user_id);

revoke insert, update, delete on public.push_tokens from authenticated;

create function public.register_push_token(p_token text, p_env text default 'production')
returns void
language plpgsql security definer set search_path = '' as $$
begin
  -- zabanovaný není člen
  if not private.is_member() then raise exception 'not a member'; end if;
  if p_token is null or p_token !~ '^[0-9a-f]{64,200}$' then raise exception 'invalid token'; end if;
  if p_env not in ('production', 'sandbox') then raise exception 'invalid env'; end if;

  insert into public.push_tokens (token, user_id, env, updated_at)
  values (p_token, auth.uid(), p_env, now())
  on conflict (token) do update set user_id = excluded.user_id, env = excluded.env, updated_at = now();
end;
$$;

-- Odhlášení: smaže jen vlastní token.
create function public.unregister_push_token(p_token text)
returns void
language sql security definer set search_path = '' as $$
  delete from public.push_tokens where token = p_token and user_id = auth.uid();
$$;

revoke execute on function public.register_push_token(text, text) from public, anon;
revoke execute on function public.unregister_push_token(text) from public, anon;
grant execute on function public.register_push_token(text, text) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;

-- ---------------------------------------------------------------------
-- Fronta
-- ---------------------------------------------------------------------

-- Řádek je ve frontě (částečný index notifications_push_queue_idx).
-- Připravený k odeslání = ve frontě, čerstvý (< 1 den), reakce ne dřív než hodinu
-- po minulém pushi na stejnou kartu, nastavení dovolí poslat teď a uživatel má token.
create function private.push_ready(n public.notifications, p_now timestamptz default now())
returns boolean language sql stable set search_path = '' as $$
  select (n.pushed_at is null or n.pushed_at < n.created_at)
     and n.created_at > p_now - interval '1 day'
     and not (n.kind = 'reaction' and n.pushed_at is not null and n.pushed_at > p_now - interval '1 hour')
     and exists (select 1 from public.push_tokens t where t.user_id = n.user_id)
     and private.push_decision(n, p_now) = 'send';
$$;

-- Každou minutu. Vrací počet připravených (kvůli testům).
create function private.push_tick(p_now timestamptz default now())
returns int
language plpgsql security definer set search_path = '' as $$
declare
  v_ready  int;
  v_url    text := (select value from private.app_config where key = 'push_function_url');
  v_secret text := (select value from private.app_config where key = 'push_secret');
begin
  -- Úklid: tohle už nikdy neodejde. Ven z fronty, ať zůstane malá.
  --   - starší než den (i první zapnutí – nepřijde dávka starých),
  --   - uživatel nemá žádný token (po registraci dostane jen nové),
  --   - kategorie vypnutá ('skip'; po zapnutí se staré nedoženou).
  update public.notifications n set pushed_at = p_now
  where (n.pushed_at is null or n.pushed_at < n.created_at)
    and (n.created_at <= p_now - interval '1 day'
         or not exists (select 1 from public.push_tokens t where t.user_id = n.user_id)
         or private.push_decision(n, p_now) = 'skip');

  select count(*) into v_ready
  from public.notifications n
  where (n.pushed_at is null or n.pushed_at < n.created_at)
    and private.push_ready(n, p_now);

  if v_ready > 0 and v_url is not null
     and to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is not null then
    execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)'
      using v_url, '{}'::jsonb,
            jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', coalesce(v_secret, '')),
            30000;
  end if;
  return v_ready;
end;
$$;

-- Text pushe: víc notifikací naráz (ráno po nočním klidu) = jeden push
-- s nejnovější a „+2 další“, klepnutí otevře zvoneček.
create function private.push_link(n public.notifications)
returns jsonb language sql stable set search_path = '' as $$
  select case
    when n.kind = 'weekly_recap' and n.payload ? 'week_start'
      then jsonb_build_object('t', 'recap', 'week_start', n.payload ->> 'week_start')
    when n.kind in ('friend_request', 'friend_accepted') and p.id is not null
      then jsonb_build_object('t', 'profile', 'profile', jsonb_build_object(
             'id', p.id, 'username', p.username, 'display_name', p.display_name,
             'avatar_path', p.avatar_path, 'timezone', p.timezone))
    when n.post_id is not null then jsonb_build_object('t', 'post', 'id', n.post_id)
    when n.challenge_id is not null then jsonb_build_object('t', 'challenge', 'id', n.challenge_id)
    else jsonb_build_object('t', 'notifications')
  end
  from (select 1) x left join public.profiles p on p.id = n.actor_id;
$$;

-- Pro send-push (service role). Zamkne připravené řádky, nastaví pushed_at
-- a vrátí dávku: jeden push na uživatele, tokeny, badge = nepřečtené.
-- Odpověď: { "jwt": {token, iat} | null, "pushes": [{user_id, tokens:[{token,env}], body, badge, link, collapse_id}] }
create table private.apns_jwt (
  id         boolean primary key default true check (id),
  token      text not null,
  issued_at  timestamptz not null
);

create function public.claim_push_batch(p_limit int default 500, p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_pushes jsonb;
begin
  with claimed as (
    update public.notifications n set pushed_at = p_now
    where n.id in (
      select q.id from public.notifications q
      where (q.pushed_at is null or q.pushed_at < q.created_at)
        and private.push_ready(q, p_now)
      order by q.created_at
      limit p_limit
      for update skip locked)
    returning n.*
  ),
  per_user as (
    select c.user_id,
           count(*) as cnt,
           (array_agg(c.id order by c.created_at desc))[1] as latest_id
    from claimed c
    group by c.user_id
  ),
  -- text a odkaz z celého řádku (CTE vrací record, funkce chtějí public.notifications)
  u as (
    select pu.user_id, pu.cnt, l as latest
    from per_user pu join public.notifications l on l.id = pu.latest_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', u.user_id,
           'tokens', (select jsonb_agg(jsonb_build_object('token', t.token, 'env', t.env))
                      from public.push_tokens t where t.user_id = u.user_id),
           'body', public.notification_text(u.latest)
                   || case when u.cnt > 1
                        then E'\n+' || (u.cnt - 1) || case when u.cnt - 1 <= 4 then ' další' else ' dalších' end
                        else '' end,
           'badge', (select count(*) from public.notifications r where r.user_id = u.user_id and r.read_at is null),
           'link', case when u.cnt > 1 then '{"t": "notifications"}'::jsonb else private.push_link(u.latest) end,
           -- reakce na stejnou kartu: novější push nahradí starší
           'collapse_id', case when u.cnt = 1 and (u.latest).kind = 'reaction'
                            then 'r-' || (u.latest).post_id end)), '[]'::jsonb)
    into v_pushes
  from u;

  return jsonb_build_object(
    'jwt', (select jsonb_build_object('token', j.token, 'iat', extract(epoch from j.issued_at)::bigint)
            from private.apns_jwt j),
    'pushes', v_pushes);
end;
$$;

-- Po odeslání: smazat tokeny, které APNs odmítl (410 Unregistered, BadDeviceToken…),
-- a uložit nový JWT (APNs nechce nový token častěji než jednou za 20 min;
-- Edge Function startuje často „za studena“, cache v paměti nestačí).
-- p_clear_jwt: APNs vrátil ExpiredProviderToken / InvalidProviderToken.
create function public.finish_push_batch(p_invalid_tokens text[] default '{}',
                                         p_jwt text default null, p_jwt_iat bigint default null,
                                         p_clear_jwt boolean default false)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.push_tokens where token = any (coalesce(p_invalid_tokens, '{}'));
  if p_clear_jwt then
    delete from private.apns_jwt;
  end if;
  if p_jwt is not null and p_jwt_iat is not null then
    insert into private.apns_jwt (id, token, issued_at) values (true, p_jwt, to_timestamp(p_jwt_iat))
    on conflict (id) do update set token = excluded.token, issued_at = excluded.issued_at;
  end if;
end;
$$;

revoke execute on function private.push_ready(public.notifications, timestamptz) from public, anon, authenticated;
revoke execute on function private.push_tick(timestamptz) from public, anon, authenticated;
revoke execute on function private.push_link(public.notifications) from public, anon, authenticated;
revoke execute on function public.claim_push_batch(int, timestamptz) from public, anon, authenticated;
revoke execute on function public.finish_push_batch(text[], text, bigint, boolean) from public, anon, authenticated;
grant execute on function public.claim_push_batch(int, timestamptz) to service_role;
grant execute on function public.finish_push_batch(text[], text, bigint, boolean) to service_role;
revoke all on private.apns_jwt from public, anon, authenticated;

select cron.schedule('push-tick', '* * * * *', $$select private.push_tick()$$);
