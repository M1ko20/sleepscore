-- =====================================================================
-- Moderace (#15): automatické skrytí obsahu pro všechny po 3 hlášeních
-- od různých lidí, dokud ho neprojdeme (resolve_report).
--
-- Co se skryje:
--   karta     → celá karta zmizí všem kromě autora (posts.hidden_at)
--   komentář  → zmizí všem kromě autora (comments.hidden_at)
--   profil    → jen jméno (= přezdívka) a profilovka; účet, noci a výzvy dál
--   sázka     → jen text sázky (challenges.stake = null); výzva běží dál
-- Původní jméno / profilovka / sázka se schovají do private.hidden_content
-- a při dismiss se vrátí.
--
-- Počítají se jen otevřená hlášení od různých nezabanovaných členů.
-- report_content už ověřuje, že hlásící obsah vidí a že to není jeho obsah.
-- Všechno v DB (trigger), žádná Edge Function.
-- =====================================================================

alter table public.posts    add column hidden_at timestamptz;  -- skryto všem kromě autora (hlášení)
alter table public.comments add column hidden_at timestamptz;

-- Práh jde změnit bez migrace: insert into private.app_config values ('auto_hide_threshold', '5');
create table private.hidden_content (
  target_kind public.report_target not null,
  target_id   uuid not null,
  owner_id    uuid references public.profiles (id) on delete cascade,  -- smazání účtu = pryč
  original    jsonb not null default '{}'::jsonb,                       -- profil/sázka: co jsme schovali
  hidden_at   timestamptz not null default now(),
  primary key (target_kind, target_id)
);
revoke all on private.hidden_content from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- RLS: skrytou kartu a komentář vidí jen autor
-- ---------------------------------------------------------------------
-- can_view_post používají i komentáře a reakce → na skrytou kartu nejde
-- komentovat ani reagovat a její komentáře nejsou vidět.
create or replace function private.can_view_post(p_post uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.posts p
    where p.id = p_post
      and (p.hidden_at is null or p.user_id = auth.uid())
      and (
        (p.kind = 'night' and private.are_friends(auth.uid(), p.user_id))
        or (p.kind = 'challenge_result' and private.can_view_challenge(p.challenge_id))
      )
  );
$$;

drop policy comments_select on public.comments;
create policy comments_select on public.comments for select to authenticated
  using (private.can_view_post(post_id)
         and (hidden_at is null or user_id = auth.uid())
         and not private.is_blocked(auth.uid(), user_id)
         and not private.reported_by_me('comment', id));

-- Skryté jméno / profilovku nejde do kontroly změnit (jinak by se skrytí
-- dalo hned obejít). Platí jen pro klienta; naše funkce běží jako postgres.
create function private.is_hidden(p_kind public.report_target, p_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from private.hidden_content where target_kind = p_kind and target_id = p_id);
$$;

-- security invoker: current_user je tu role volajícího (authenticated),
-- v našich security definer funkcích postgres.
create function private.guard_hidden_profile()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user in ('authenticated', 'anon')
     and (new.display_name is distinct from old.display_name
          or new.avatar_path is distinct from old.avatar_path)
     and private.is_hidden('profile', old.id) then
    raise exception 'profile hidden pending review';
  end if;
  return new;
end;
$$;
create trigger profiles_guard_hidden before update on public.profiles
  for each row execute function private.guard_hidden_profile();

-- ---------------------------------------------------------------------
-- Skrytí a zviditelnění
-- ---------------------------------------------------------------------
create function private.hide_content(p_kind public.report_target, p_id uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_owner    uuid;
  v_original jsonb := '{}'::jsonb;
begin
  if exists (select 1 from private.hidden_content where target_kind = p_kind and target_id = p_id) then
    return false;
  end if;

  if p_kind = 'post' then
    update public.posts set hidden_at = now() where id = p_id and hidden_at is null
    returning user_id into v_owner;
  elsif p_kind = 'comment' then
    update public.comments set hidden_at = now() where id = p_id and hidden_at is null
    returning user_id into v_owner;
    -- text komentáře v notifikaci majitele karty
    update public.notifications set payload = payload - 'text'
    where comment_id = p_id and kind = 'comment';
  elsif p_kind = 'profile' then
    select id, jsonb_build_object('display_name', display_name, 'avatar_path', avatar_path)
      into v_owner, v_original
    from public.profiles where id = p_id;
    update public.profiles set display_name = username, avatar_path = null where id = p_id;
  elsif p_kind = 'challenge' then
    select creator_id, jsonb_build_object('stake', stake) into v_owner, v_original
    from public.challenges where id = p_id and stake is not null;
    if found then
      update public.challenges set stake = null where id = p_id;
    end if;
  end if;

  if v_owner is null then return false; end if;  -- obsah už neexistuje / není co skrýt

  insert into private.hidden_content (target_kind, target_id, owner_id, original)
  values (p_kind, p_id, v_owner, v_original);
  return true;
end;
$$;

-- p_restore = true (dismiss): vrátí obsah; false (remove/ban): obsah už
-- je smazaný, jen zruší skrytí (karta bez textu a fotky je zase vidět).
create function private.unhide_content(p_kind public.report_target, p_id uuid, p_restore boolean)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_original jsonb;
  c public.challenges;
  v_winner uuid;
begin
  delete from private.hidden_content where target_kind = p_kind and target_id = p_id
  returning original into v_original;

  if p_kind = 'post' then
    update public.posts set hidden_at = null where id = p_id;
  elsif p_kind = 'comment' then
    update public.comments set hidden_at = null where id = p_id;
    if p_restore then
      update public.notifications n set payload = n.payload || jsonb_build_object('text', left(cm.body, 140))
      from public.comments cm
      where cm.id = p_id and n.comment_id = p_id and n.kind = 'comment';
    end if;
  elsif v_original is not null and p_restore then
    if p_kind = 'profile' then
      update public.profiles
      set display_name = coalesce(v_original ->> 'display_name', display_name),
          avatar_path  = coalesce(avatar_path, v_original ->> 'avatar_path')
      where id = p_id;
    elsif p_kind = 'challenge' then
      update public.challenges set stake = coalesce(stake, v_original ->> 'stake')
      where id = p_id
      returning * into c;
      -- Výzva skončila, zatímco byla sázka skrytá → dluhy nevznikly; doplnit.
      if c.status = 'finished' and c.type <> 'team_goal' and c.stake is not null
         and not exists (select 1 from public.debts where challenge_id = p_id) then
        select user_id into v_winner from public.challenge_participants
        where challenge_id = p_id and result = 'win';
        if v_winner is not null then
          insert into public.debts (challenge_id, debtor_id, creditor_id, stake)
          select p_id, user_id, v_winner, c.stake
          from public.challenge_participants where challenge_id = p_id and result = 'loss';
        end if;
      end if;
    end if;
  end if;
end;
$$;

-- Po každém novém hlášení: dosáhl obsah prahu? → skrýt + upozornit nás.
create function private.on_report_auto_hide()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_threshold int := coalesce((select value::int from private.app_config where key = 'auto_hide_threshold'), 3);
  v_count int;
begin
  select count(distinct r.reporter_id) into v_count
  from public.reports r
  join public.profiles pr on pr.id = r.reporter_id and pr.banned_at is null
  where r.target_kind = new.target_kind and r.target_id = new.target_id
    and r.status = 'open'
    and r.reporter_id is distinct from r.reported_user_id;

  if v_count >= v_threshold and private.hide_content(new.target_kind, new.target_id) then
    perform private.send_admin_alert(
      'Obsah automaticky skrytý po ' || v_count || ' hlášeních',
      'Druh: ' || new.target_kind || '. Skryto všem kromě autora, dokud to neprojdeš.' ||
      E'\nid: ' || new.target_id);
  end if;
  return null;
end;
$$;
-- (po reports_alert – triggery běží podle abecedy)
create trigger reports_auto_hide after insert on public.reports
  for each row execute function private.on_report_auto_hide();

-- ---------------------------------------------------------------------
-- Vyřízení: dismiss vrátí skrytý obsah, remove/ban zruší skrytí
-- ---------------------------------------------------------------------
create or replace function private.resolve_report(p_report uuid, p_action text, p_note text default null)
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

  perform private.unhide_content(r.target_kind, r.target_id, p_action = 'dismiss');

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
  private.guard_hidden_profile(),
  private.hide_content(public.report_target, uuid),
  private.unhide_content(public.report_target, uuid, boolean),
  private.on_report_auto_hide(),
  private.resolve_report(uuid, text, text)
from public, anon, authenticated;
revoke execute on function private.is_hidden(public.report_target, uuid) from public, anon;
grant execute on function private.is_hidden(public.report_target, uuid) to authenticated;
