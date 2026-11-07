-- =====================================================================
-- Moderace (App Store, pravidlo 1.2): nahlášení obsahu, blokování
-- uživatelů, upozornění pro nás a nástroje na vyřízení hlášení.
--
-- Všechno v DB (RLS + RPC + pg_cron), žádná Edge Function.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Blokování
-- ---------------------------------------------------------------------
-- Blokovaný se o bloku nedozví (řádek vidí jen ten, kdo blokoval).
create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index blocks_blocked_idx on public.blocks (blocked_id);

alter table public.blocks enable row level security;
revoke all on public.blocks from anon, authenticated;
grant select on public.blocks to authenticated;
create policy blocks_select on public.blocks for select to authenticated
  using (blocker_id = auth.uid());

-- Je mezi dvojicí blok (jakýmkoliv směrem)?
create function private.is_blocked(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)
  );
$$;

-- Zablokování: zruší přátelství i čekající žádost, zruší čekající souboj
-- mezi nimi a vyřadí druhého z čekající skupinové výzvy, kterou jeden z nich
-- založil. Běžící výzvy doběhnou (jinak by šlo blokem utéct před prohrou).
create function public.block_user(p_user uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
begin
  if not private.is_member() then raise exception 'not a member'; end if;
  if p_user = v_me then raise exception 'cannot block yourself'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then
    raise exception 'user not found';
  end if;

  insert into public.blocks (blocker_id, blocked_id) values (v_me, p_user)
  on conflict do nothing;

  delete from public.friendships
  where user_a = least(v_me, p_user) and user_b = greatest(v_me, p_user);

  update public.challenges c set status = 'cancelled'
  where c.status = 'pending' and c.type = 'duel'
    and exists (select 1 from public.challenge_participants cp
                where cp.challenge_id = c.id and cp.user_id = v_me)
    and exists (select 1 from public.challenge_participants cp
                where cp.challenge_id = c.id and cp.user_id = p_user);

  update public.challenge_participants cp
  set status = 'declined', responded_at = now()
  from public.challenges c
  where c.id = cp.challenge_id and c.status = 'pending' and c.type <> 'duel'
    and cp.status <> 'declined'
    and ((c.creator_id = v_me and cp.user_id = p_user)
      or (c.creator_id = p_user and cp.user_id = v_me));
end;
$$;

-- Odblokování. Přátelství se neobnoví – je potřeba nová žádost.
create function public.unblock_user(p_user uuid)
returns void
language sql security definer set search_path = '' as $$
  delete from public.blocks where blocker_id = auth.uid() and blocked_id = p_user;
$$;

revoke execute on function public.block_user(uuid), public.unblock_user(uuid) from public, anon;
grant execute on function public.block_user(uuid), public.unblock_user(uuid) to authenticated;

-- Žádost o přátelství: s blokem nejde (ani jedním směrem).
create or replace function public.send_friend_request(p_user uuid)
returns public.friendship_status
language plpgsql security definer set search_path = '' as $$
declare
  v_row public.friendships;
begin
  if not private.is_member() then raise exception 'not a member'; end if;
  if p_user = auth.uid() then raise exception 'cannot befriend yourself'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then
    raise exception 'user not found';
  end if;
  if exists (select 1 from public.blocks where blocker_id = auth.uid() and blocked_id = p_user) then
    raise exception 'you blocked this user';
  end if;
  if exists (select 1 from public.blocks where blocker_id = p_user and blocked_id = auth.uid()) then
    raise exception 'not allowed';
  end if;

  select * into v_row from public.friendships
  where user_a = least(auth.uid(), p_user) and user_b = greatest(auth.uid(), p_user)
  for update;

  if not found then
    insert into public.friendships (user_a, user_b, requested_by)
    values (least(auth.uid(), p_user), greatest(auth.uid(), p_user), auth.uid());
    return 'pending';
  elsif v_row.status = 'pending' and v_row.requested_by <> auth.uid() then
    update public.friendships set status = 'accepted', accepted_at = now()
    where user_a = v_row.user_a and user_b = v_row.user_b;
    return 'accepted';
  else
    return v_row.status;
  end if;
end;
$$;

-- Výzvy jdou jen s přáteli a blok přátelství ruší → create_challenge
-- blok hlídá sám. Skupinovou výzvu, kterou založí někdo třetí, můžou hrát
-- i dva lidé s blokem mezi sebou (vidí jen skóre, ne noci).

-- ---------------------------------------------------------------------
-- Hlášení
-- ---------------------------------------------------------------------
create type public.report_target as enum ('post', 'comment', 'profile', 'challenge');
create type public.report_status as enum ('open', 'resolved', 'dismissed');

create table public.reports (
  id               uuid primary key default gen_random_uuid(),
  reporter_id      uuid references public.profiles (id) on delete set null,
  target_kind      public.report_target not null,
  target_id        uuid not null,
  reported_user_id uuid references public.profiles (id) on delete set null,
  reason           text not null check (reason in ('harassment', 'hate', 'sexual', 'spam', 'other')),
  note             text check (char_length(note) <= 500),
  snapshot         jsonb not null,           -- kopie obsahu v době hlášení (autor ho může smazat)
  status           public.report_status not null default 'open',
  created_at       timestamptz not null default now(),
  reminded_at      timestamptz,
  resolved_at      timestamptz,
  resolution       text,                     -- dismiss | remove | ban + poznámka
  unique (reporter_id, target_kind, target_id)
);
create index reports_open_idx on public.reports (created_at) where status = 'open';
create index reports_target_idx on public.reports (target_kind, target_id);

-- Klient do tabulky nesmí vůbec (ani číst). Zápis jen přes report_content.
alter table public.reports enable row level security;
revoke all on public.reports from anon, authenticated;

-- Nahlásil jsem tohle? (nahlášený obsah se mi hned skryje)
create function private.reported_by_me(p_kind public.report_target, p_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.reports
    where reporter_id = auth.uid() and target_kind = p_kind and target_id = p_id
  );
$$;

-- Nahlášení. Obsah musí volající vidět. p_block = rovnou autora zablokovat.
create function public.report_content(
  p_kind   public.report_target,
  p_target uuid,
  p_reason text,
  p_note   text default null,
  p_block  boolean default false
)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_me       uuid := auth.uid();
  v_user     uuid;
  v_snapshot jsonb;
  v_id       uuid;
begin
  if not private.is_member() then raise exception 'not a member'; end if;

  if p_kind = 'post' then
    select p.user_id, jsonb_build_object('title', p.title, 'body', p.body,
                                         'photo_path', p.photo_path, 'night_id', p.night_id)
      into v_user, v_snapshot
    from public.posts p
    where p.id = p_target and p.kind = 'night' and private.can_view_post(p.id);
  elsif p_kind = 'comment' then
    select c.user_id, jsonb_build_object('body', c.body, 'post_id', c.post_id)
      into v_user, v_snapshot
    from public.comments c
    where c.id = p_target and private.can_view_post(c.post_id);
  elsif p_kind = 'profile' then
    select pr.id, jsonb_build_object('username', pr.username, 'display_name', pr.display_name,
                                     'avatar_path', pr.avatar_path)
      into v_user, v_snapshot
    from public.profiles pr
    where pr.id = p_target;
  elsif p_kind = 'challenge' then
    select c.creator_id, jsonb_build_object('stake', c.stake, 'type', c.type)
      into v_user, v_snapshot
    from public.challenges c
    where c.id = p_target and private.can_view_challenge(c.id);
  end if;

  if v_snapshot is null then raise exception 'content not found'; end if;
  if v_user = v_me then raise exception 'cannot report yourself'; end if;

  if (select count(*) from public.reports
      where reporter_id = v_me and created_at > now() - interval '1 day') >= 20 then
    raise exception 'too many reports';
  end if;

  insert into public.reports (reporter_id, target_kind, target_id, reported_user_id,
                              reason, note, snapshot)
  values (v_me, p_kind, p_target, v_user, p_reason,
          nullif(left(trim(coalesce(p_note, '')), 500), ''), v_snapshot)
  on conflict (reporter_id, target_kind, target_id) do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.reports
    where reporter_id = v_me and target_kind = p_kind and target_id = p_target;
  end if;

  if p_block and v_user is not null then
    perform public.block_user(v_user);
  end if;

  return v_id;
end;
$$;
revoke execute on function public.report_content(public.report_target, uuid, text, text, boolean) from public, anon;
grant execute on function public.report_content(public.report_target, uuid, text, text, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- RLS: blok a vlastní hlášení skrývají obsah
-- ---------------------------------------------------------------------
-- Karty: nahlášenou kartu už nevidím. (Noci blokovaného nevidím i tak –
-- blok ruší přátelství.)
drop policy posts_select on public.posts;
create policy posts_select on public.posts for select to authenticated
  using (private.can_view_post(id) and not private.reported_by_me('post', id));

-- Komentáře: nevidím komentáře blokovaných (oběma směry) ani nahlášené.
-- Komentovat nejde kartu člověka, se kterým je blok.
drop policy comments_select on public.comments;
create policy comments_select on public.comments for select to authenticated
  using (private.can_view_post(post_id)
         and not private.is_blocked(auth.uid(), user_id)
         and not private.reported_by_me('comment', id));

drop policy comments_insert on public.comments;
create policy comments_insert on public.comments for insert to authenticated
  with check (user_id = auth.uid() and private.can_view_post(post_id)
              and not exists (select 1 from public.posts p
                              where p.id = post_id and private.is_blocked(auth.uid(), p.user_id)));

-- Reakce: totéž.
drop policy reactions_select on public.reactions;
create policy reactions_select on public.reactions for select to authenticated
  using (private.can_view_post(post_id) and not private.is_blocked(auth.uid(), user_id));

drop policy reactions_insert on public.reactions;
create policy reactions_insert on public.reactions for insert to authenticated
  with check (user_id = auth.uid() and private.can_view_post(post_id)
              and not exists (select 1 from public.posts p
                              where p.id = post_id and private.is_blocked(auth.uid(), p.user_id)));

-- ---------------------------------------------------------------------
-- Zákaz účtu (ban)
-- ---------------------------------------------------------------------
alter table public.profiles add column banned_at timestamptz;

-- Zabanovaný není člen → nevidí nic a nemůže volat RPC, i když má ještě
-- platný JWT (max. 1 h). Přihlásit se nemůže kvůli auth.users.banned_until.
create or replace function private.is_member()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and banned_at is null);
$$;

-- ---------------------------------------------------------------------
-- Upozornění pro nás: webhook přes pg_net (bez Edge Function).
-- URL se nastavuje ručně v DB, do gitu nepatří:
--   insert into private.app_config values ('report_webhook_url', 'https://discord.com/api/webhooks/…');
--   insert into private.app_config values ('report_webhook_format', 'discord');   -- discord | slack | ntfy
-- ntfy: URL je https://ntfy.sh/<tajné-téma>.
-- Ve zprávě není obsah ani jména – jen druh, důvod a id (detail v DB).
-- ---------------------------------------------------------------------
create table private.app_config (
  key   text primary key,
  value text not null
);
revoke all on private.app_config from public, anon, authenticated;

do $$
begin
  create extension if not exists pg_net;
exception when others then
  raise notice 'pg_net není k dispozici – upozornění na hlášení se nebudou posílat';
end;
$$;

create function private.send_admin_alert(p_title text, p_message text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_url    text := (select value from private.app_config where key = 'report_webhook_url');
  v_format text := coalesce((select value from private.app_config where key = 'report_webhook_format'), 'discord');
  v_body   jsonb;
begin
  if v_url is null or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then
    return;
  end if;

  if v_format = 'ntfy' then
    -- JSON publikace jde na kořen serveru s tématem v těle.
    v_body := jsonb_build_object('topic', regexp_replace(v_url, '^.*/', ''),
                                 'title', p_title, 'message', p_message, 'priority', 4);
    v_url := regexp_replace(v_url, '/[^/]*$', '');
  elsif v_format = 'slack' then
    v_body := jsonb_build_object('text', p_title || E'\n' || p_message);
  else
    v_body := jsonb_build_object('content', '**' || p_title || E'**\n' || p_message);
  end if;

  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using v_url, v_body, '{"Content-Type": "application/json"}'::jsonb;
exception when others then
  -- Upozornění nesmí shodit uložení hlášení.
  raise warning 'admin alert failed: %', sqlerrm;
end;
$$;

create function private.on_report_insert()
returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform private.send_admin_alert(
    'Nové hlášení (' || new.target_kind || ', ' || new.reason || ')',
    'Otevřených: ' || (select count(*) from public.reports where status = 'open') ||
    E'. Vyřídit do 24 h.\nid: ' || new.id);
  return new;
end;
$$;
create trigger reports_alert after insert on public.reports
  for each row execute function private.on_report_insert();

-- Připomínka: hlášení otevřené přes 12 h → jednou připomenout (pg_cron).
create function private.remind_open_reports()
returns int
language plpgsql security definer set search_path = '' as $$
declare
  n int;
begin
  update public.reports set reminded_at = now()
  where status = 'open' and reminded_at is null and created_at < now() - interval '12 hours';
  get diagnostics n = row_count;
  if n > 0 then
    perform private.send_admin_alert(
      'Hlášení čekají přes 12 h: ' || n,
      'Nejstarší z ' || (select to_char(min(created_at) at time zone 'Europe/Prague', 'DD. MM. HH24:MI')
                         from public.reports where status = 'open') ||
      '. Slíbili jsme reakci do 24 h.');
  end if;
  return n;
end;
$$;

select cron.schedule('report-reminder', '35 * * * *', $$select private.remind_open_reports()$$);

-- ---------------------------------------------------------------------
-- Vyřízení hlášení (ručně v SQL editoru Supabase, jako postgres)
--   select * from public.reports where status = 'open' order by created_at;
--   select private.resolve_report('<id>', 'dismiss' | 'remove' | 'ban', 'poznámka');
-- ---------------------------------------------------------------------
create function private.ban_user(p_user uuid, p_note text default null)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.profiles set banned_at = now(), avatar_path = null where id = p_user;
  if not found then raise exception 'user not found'; end if;

  -- Přihlášení: GoTrue odmítne obnovu tokenu.
  update auth.users set banned_until = 'infinity' where id = p_user;

  -- Zmizí z feedů (noci vidí jen přátelé), komentáře a reakce pryč,
  -- nepoužité pozvánky neplatí, čekající výzvy zrušené. Běžící souboje
  -- doběhnou (zabanovaný už nic nenahraje → nuly).
  delete from public.friendships where p_user in (user_a, user_b);
  delete from public.comments where user_id = p_user;
  delete from public.reactions where user_id = p_user;
  delete from public.invites where inviter_id = p_user and redeemed_by is null;
  delete from public.push_tokens where user_id = p_user;
  update public.posts set title = null, body = null, photo_path = null where user_id = p_user;
  update public.challenges c set status = 'cancelled'
  where c.status = 'pending'
    and exists (select 1 from public.challenge_participants cp
                where cp.challenge_id = c.id and cp.user_id = p_user);
  raise notice 'banned %: %. Fotky v Storage (avatars/night-photos/%/) smaž ručně.', p_user, p_note, p_user;
end;
$$;

create function private.unban_user(p_user uuid)
returns void
language sql security definer set search_path = '' as $$
  update public.profiles set banned_at = null where id = p_user;
  update auth.users set banned_until = null where id = p_user;
$$;

create function private.resolve_report(p_report uuid, p_action text, p_note text default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  r public.reports;
begin
  select * into r from public.reports where id = p_report;
  if not found then raise exception 'report not found'; end if;
  if p_action not in ('dismiss', 'remove', 'ban') then
    raise exception 'action must be dismiss, remove or ban';
  end if;

  if p_action in ('remove', 'ban') then
    if r.target_kind = 'comment' then
      delete from public.comments where id = r.target_id;
    elsif r.target_kind = 'post' then
      -- Noc (data ze zařízení) zůstává, maže se jen to, co člověk napsal/nahrál.
      update public.posts set title = null, body = null, photo_path = null where id = r.target_id;
    elsif r.target_kind = 'profile' then
      update public.profiles set display_name = username, avatar_path = null where id = r.target_id;
    elsif r.target_kind = 'challenge' then
      update public.challenges set stake = null where id = r.target_id;
    end if;
  end if;

  if p_action = 'ban' and r.reported_user_id is not null then
    perform private.ban_user(r.reported_user_id, p_note);
  end if;

  -- Vyřídí všechna otevřená hlášení stejného obsahu.
  update public.reports
  set status = case when p_action = 'dismiss' then 'dismissed'::public.report_status
                    else 'resolved'::public.report_status end,
      resolved_at = now(),
      resolution = p_action || coalesce(': ' || p_note, '')
  where status = 'open'
    and (id = p_report or (target_kind = r.target_kind and target_id = r.target_id));

  if p_action <> 'dismiss' and r.snapshot ? 'photo_path' and r.snapshot ->> 'photo_path' is not null then
    raise notice 'Smaž ručně soubor night-photos/%', r.snapshot ->> 'photo_path';
  end if;
end;
$$;

revoke execute on function
  private.is_blocked(uuid, uuid),
  private.reported_by_me(public.report_target, uuid),
  private.send_admin_alert(text, text),
  private.on_report_insert(),
  private.remind_open_reports(),
  private.ban_user(uuid, text),
  private.unban_user(uuid),
  private.resolve_report(uuid, text, text)
from public, anon, authenticated;
-- RLS helpery musí volat i přihlášený (politiky běží s jeho právy).
grant execute on function private.is_blocked(uuid, uuid),
                          private.reported_by_me(public.report_target, uuid) to authenticated;
