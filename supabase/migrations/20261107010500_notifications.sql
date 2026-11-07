-- =====================================================================
-- Notifikace (zvoneček v appce). Issue #9.
--
-- Vznikají jen v databázi: triggery na tabulkách a pg_cron. Žádná Edge
-- Function, žádný polling z appky (počet nepřečtených se načítá s feedem).
--
-- Navazuje:
--   #10 push přes APNs – fronta = řádky, které potřebují push (index
--       notifications_push_queue_idx), odesílač nastaví pushed_at. Text
--       pushe = stejná funkce jako ve zvonečku (public.notification_text).
--   #11 nastavení – sloupec `category` odpovídá přepínačům v nastavení;
--       zvoneček ukazuje vše, filtr podle notification_prefs dělá odesílač.
-- =====================================================================

create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,   -- příjemce
  kind         text not null check (kind in (
                 'reaction', 'comment',
                 'friend_request', 'friend_accepted',
                 'challenge_invite', 'challenge_response', 'challenge_started',
                 'challenge_ending', 'challenge_result', 'debt_settled',
                 'achievement', 'night_ready', 'weekly_recap')),
  -- kategorie pro nastavení (#11): reactions, comments, friends, challenges,
  -- achievements, morning, recap
  category     text generated always as (case
                 when kind = 'reaction' then 'reactions'
                 when kind = 'comment' then 'comments'
                 when kind in ('friend_request', 'friend_accepted') then 'friends'
                 when kind = 'achievement' then 'achievements'
                 when kind = 'night_ready' then 'morning'
                 when kind = 'weekly_recap' then 'recap'
                 else 'challenges' end) stored,
  actor_id     uuid references public.profiles (id) on delete set null,        -- kdo to způsobil (null = appka)
  post_id      uuid references public.posts (id) on delete cascade,            -- proklik na kartu
  challenge_id uuid references public.challenges (id) on delete cascade,       -- proklik na výzvu
  comment_id   uuid references public.comments (id) on delete cascade,         -- smazaný komentář = pryč i notifikace
  payload      jsonb not null default '{}'::jsonb,                             -- fakta pro text (bez jmen – ta se čtou živě)
  count        int not null default 1 check (count >= 1),                      -- reakce: kolik lidí reagovalo
  read_at      timestamptz,
  pushed_at    timestamptz,                                                    -- #10: kdy odešel push
  created_at   timestamptz not null default now(),                             -- čas poslední události (reakce ho posouvají)
  check (actor_id is distinct from user_id)                                    -- nikdy sám sobě
);

create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_unread_idx on public.notifications (user_id) where read_at is null;
create index notifications_created_idx on public.notifications (created_at);
-- #10: fronta na push. Reakce se slučují: po další reakci je created_at > pushed_at,
-- odesílač ji pošle znovu nejdřív hodinu po minulém pushi.
create index notifications_push_queue_idx on public.notifications (created_at)
  where pushed_at is null or pushed_at < created_at;

-- Jeden řádek na kartu u reakcí, jedno „zítra konec“ na výzvu, jeden recap na týden.
create unique index notifications_reaction_key on public.notifications (user_id, post_id) where kind = 'reaction';
create unique index notifications_night_ready_key on public.notifications (user_id, post_id) where kind = 'night_ready';
create unique index notifications_ending_key on public.notifications (user_id, challenge_id) where kind = 'challenge_ending';
create unique index notifications_recap_key on public.notifications (user_id, (payload ->> 'week_start')) where kind = 'weekly_recap';

alter table public.notifications enable row level security;
revoke all on public.notifications from anon, authenticated;
grant select on public.notifications to authenticated;
create policy notifications_select on public.notifications for select to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- RPC: otevření zvonečku označí vše jako přečtené (1 call).
-- ---------------------------------------------------------------------
create function public.mark_notifications_read()
returns int language plpgsql security definer set search_path = '' as $$
declare
  n int;
begin
  update public.notifications set read_at = now()
  where user_id = auth.uid() and read_at is null;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke execute on function public.mark_notifications_read() from public, anon;
grant execute on function public.mark_notifications_read() to authenticated;

-- ---------------------------------------------------------------------
-- Text notifikace. Počítá se při čtení (jména a skóre jsou vždy aktuální).
-- PostgREST: computed column → select=…,text:notification_text
-- Tón podle design.md: krátce, sucho, bez emoji, bez vykřičníků.
-- Slovesa v přítomném čase, ať nemusíme znát rod („Jakub přijímá“).
-- ---------------------------------------------------------------------
create function public.notification_text(n public.notifications)
returns text language plpgsql stable security invoker set search_path = '' as $$
declare
  v_actor text;
  v_name  text;
  v_score smallint;
  v_card  boolean;
  p       jsonb := n.payload;
  v_num   text;
  v_other int;
  v_cnt   int;
begin
  select display_name into v_actor from public.profiles where id = n.actor_id;
  v_actor := coalesce(v_actor, 'Někdo');

  case n.kind
  when 'reaction' then
    v_other := n.count - 1;
    if v_other <= 0 then
      return v_actor || ' reaguje na tvoji noc.';
    end if;
    return v_actor || ' a ' || v_other
           || case when v_other <= 4 then ' další' else ' dalších' end
           || ' reagují na tvoji noc.';

  when 'comment' then
    return v_actor || ': ' || coalesce(p ->> 'text', '');

  when 'friend_request' then
    return v_actor || ' ti posílá žádost o přátelství.';

  when 'friend_accepted' then
    if (p ->> 'via_invite')::boolean then
      return v_actor || ' je tu přes tvoji pozvánku.';
    end if;
    return v_actor || ' přijímá žádost o přátelství.';

  when 'challenge_invite' then
    return v_actor
      || case p ->> 'type'
           when 'duel' then ' tě vyzývá: '
           when 'free_for_all' then ' tě zve do výzvy všichni proti všem: '
           else ' tě zve do společného cíle ' || (p ->> 'target_score') || ': '
         end
      || (p ->> 'duration_days') || ' dní'
      || coalesce(', ' || (p ->> 'stake'), '') || '.';

  when 'challenge_response' then
    if (p ->> 'accepted')::boolean then
      return v_actor || ' jde do toho.';
    end if;
    return v_actor || ' výzvu odmítá.';

  when 'challenge_started' then
    if p ->> 'type' = 'duel' and n.actor_id is not null then
      return v_actor || ' výzvu přijímá. Start ' || to_char((p ->> 'start_date')::date, 'FMDD. FMMM.')
             || ', ' || (p ->> 'duration_days') || ' dní.';
    end if;
    return 'Výzva startuje ' || to_char((p ->> 'start_date')::date, 'FMDD. FMMM.')
           || '. ' || (p ->> 'duration_days') || ' dní' || coalesce(', ' || (p ->> 'stake'), '') || '.';

  when 'challenge_ending' then
    v_num := replace(to_char(abs((p ->> 'diff')::numeric), 'FM990.0'), '.', ',');
    return 'Zítra konec. ' || case p ->> 'mode'
      when 'lead'  then 'Vedeš o ' || v_num || ' bodu.'
      when 'trail' then 'Prohráváš o ' || v_num || ' bodu.'
      when 'tie'   then 'Je to nastejno.'
      else 'Skupina má ' || replace(to_char((p ->> 'avg')::numeric, 'FM990.0'), '.', ',')
           || ', cíl je ' || (p ->> 'target_score') || '.'
    end;

  when 'challenge_result' then
    v_num := replace(to_char((p ->> 'my_avg')::numeric, 'FM990.0'), '.', ',')
             || ' : ' || replace(to_char((p ->> 'other_avg')::numeric, 'FM990.0'), '.', ',');
    if p ->> 'type' = 'team_goal' then
      return case when p ->> 'result' = 'win' then 'Cíl splněn. ' else 'Cíl nesplněn. ' end
             || 'Skupina ' || replace(to_char((p ->> 'my_avg')::numeric, 'FM990.0'), '.', ',')
             || ', cíl ' || (p ->> 'target_score') || '.';
    end if;
    case p ->> 'result'
    when 'win' then
      v_cnt := coalesce((p ->> 'souls')::int, 1);
      if v_cnt > 1 then
        return 'Vyhráno ' || v_num || '. Bereš ' || v_cnt
               || case when v_cnt <= 4 then ' duše.' else ' duší.' end;
      end if;
      return 'Vyhráno ' || v_num || '. ' || v_actor || ' přichází o duši.';
    when 'loss' then
      if p ->> 'other_result' = 'win' then
        return 'Prohra ' || v_num || '. ' || v_actor || ' bere tvoji duši.';
      end if;
      return 'Prohra ' || v_num || '.';   -- nahoře remíza, duše nikdo
    else
      return 'Remíza ' || v_num || '.';
    end case;

  when 'debt_settled' then
    return v_actor || ' hlásí splaceno: ' || coalesce(p ->> 'stake', 'sázka') || '.';

  when 'achievement' then
    select name into v_name from public.achievements where code = p ->> 'code';
    v_name := coalesce(v_name, p ->> 'code');
    if coalesce((p ->> 'times')::int, 1) > 1 then
      return v_name || '. Zase.';
    end if;
    return 'Nový odznak: ' || v_name || '.';

  when 'night_ready' then
    select ni.score, (po.title is not null or po.body is not null)
      into v_score, v_card
    from public.posts po join public.nights ni on ni.id = po.night_id
    where po.id = n.post_id;
    if v_score is null then return 'Noc je tady.'; end if;
    return 'Tvoje noc: ' || v_score || '.' || case when v_card then '' else ' Doplň komentář.' end;

  when 'weekly_recap' then
    v_cnt := (p ->> 'nights')::int;
    return 'Minulý týden v číslech: průměr '
           || replace(to_char((p ->> 'avg_score')::numeric, 'FM990'), '.', ',') || ', '
           || v_cnt || case when v_cnt = 1 then ' noc.' when v_cnt <= 4 then ' noci.' else ' nocí.' end;

  else
    return '';
  end case;
end;
$$;
revoke execute on function public.notification_text(public.notifications) from public, anon;
grant execute on function public.notification_text(public.notifications) to authenticated, service_role;

-- =====================================================================
-- Vznik notifikací – triggery
-- =====================================================================

-- Reakce: jeden řádek na kartu. Nová reakce ho aktualizuje (počet, poslední
-- reagující) a znovu označí jako nepřečtený; smazaná reakce počet sníží,
-- poslední smazaná notifikaci odstraní. Změna druhu reakce nic neposílá.
create function private.sync_reaction_notification(p_post uuid, p_bump boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_owner uuid;
  v_count int;
  v_actor uuid;
  v_kind  public.reaction_kind;
begin
  select user_id into v_owner from public.posts where id = p_post and kind = 'night';
  if v_owner is null then return; end if;   -- karta mezitím smazaná / výsledek výzvy

  select count(*) into v_count from public.reactions where post_id = p_post and user_id <> v_owner;
  if v_count = 0 then
    delete from public.notifications where user_id = v_owner and post_id = p_post and kind = 'reaction';
    return;
  end if;
  select user_id, kind into v_actor, v_kind from public.reactions
  where post_id = p_post and user_id <> v_owner
  order by created_at desc, user_id limit 1;

  if p_bump then
    insert into public.notifications (user_id, kind, actor_id, post_id, count, payload)
    values (v_owner, 'reaction', v_actor, p_post, v_count, jsonb_build_object('reaction', v_kind))
    on conflict (user_id, post_id) where kind = 'reaction' do update
      set actor_id = excluded.actor_id, count = excluded.count, payload = excluded.payload,
          created_at = now(), read_at = null;
  else
    update public.notifications
    set actor_id = v_actor, count = v_count, payload = jsonb_build_object('reaction', v_kind)
    where user_id = v_owner and post_id = p_post and kind = 'reaction';
  end if;
end;
$$;

create function private.on_reaction_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    perform private.sync_reaction_notification(new.post_id, true);
  else
    perform private.sync_reaction_notification(old.post_id, false);
  end if;
  return null;
end;
$$;
create trigger reactions_notify after insert or delete on public.reactions
  for each row execute function private.on_reaction_notify();

-- Komentář na mojí kartě (komentáře mezi sebou zatím ne).
create function private.on_comment_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_owner uuid;
begin
  select user_id into v_owner from public.posts where id = new.post_id and kind = 'night';
  if v_owner is null or v_owner = new.user_id then return null; end if;
  insert into public.notifications (user_id, kind, actor_id, post_id, comment_id, payload)
  values (v_owner, 'comment', new.user_id, new.post_id, new.id,
          jsonb_build_object('text', left(new.body, 140)));
  return null;
end;
$$;
create trigger comments_notify after insert on public.comments
  for each row execute function private.on_comment_notify();

-- Přátelství: žádost, přijetí (i automatické přátelství přes pozvánku).
-- Stažená / odmítnutá žádost zmizí i ze zvonečku.
create function private.on_friendship_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_other uuid;
begin
  if tg_op = 'DELETE' then
    if old.status = 'pending' then
      delete from public.notifications
      where kind = 'friend_request'
        and ((user_id = old.user_a and actor_id = old.user_b) or (user_id = old.user_b and actor_id = old.user_a));
    end if;
    return null;
  end if;

  v_other := case when new.requested_by = new.user_a then new.user_b else new.user_a end;
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notifications (user_id, kind, actor_id)
    values (v_other, 'friend_request', new.requested_by);
  elsif tg_op = 'INSERT' and new.status = 'accepted' then
    -- redeem_invite: pozvaný je rovnou přítel → dát vědět tomu, kdo zval
    insert into public.notifications (user_id, kind, actor_id, payload)
    values (new.requested_by, 'friend_accepted', v_other, '{"via_invite": true}');
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status = 'accepted' then
    insert into public.notifications (user_id, kind, actor_id)
    values (new.requested_by, 'friend_accepted', v_other);
  end if;
  return null;
end;
$$;
create trigger friendships_notify after insert or update of status or delete on public.friendships
  for each row execute function private.on_friendship_notify();

-- Účastníci výzvy: pozvánka (pozvanému), odpověď (zakladateli).
-- Přijatý duel hlásí rovnou start (viz challenges_notify), ať nechodí dvě.
-- Automatické „declined“ při startu skupiny (kdo nestihl odpovědět) se nehlásí.
create function private.on_participant_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  c public.challenges;
begin
  select * into c from public.challenges where id = new.challenge_id;
  if not found or c.creator_id is null then return null; end if;

  if tg_op = 'INSERT' then
    if new.status = 'invited' and new.user_id <> c.creator_id then
      insert into public.notifications (user_id, kind, actor_id, challenge_id, payload)
      values (new.user_id, 'challenge_invite', c.creator_id, c.id,
              jsonb_strip_nulls(jsonb_build_object('type', c.type, 'duration_days', c.duration_days,
                                                   'stake', c.stake, 'target_score', c.target_score)));
    end if;
  elsif old.status = 'invited' and new.status in ('accepted', 'declined')
        and c.status = 'pending' and new.user_id <> c.creator_id
        and not (c.type = 'duel' and new.status = 'accepted') then
    insert into public.notifications (user_id, kind, actor_id, challenge_id, payload)
    values (c.creator_id, 'challenge_response', new.user_id, c.id,
            jsonb_build_object('accepted', new.status = 'accepted'));
  end if;
  return null;
end;
$$;
create trigger challenge_participants_notify after insert or update of status on public.challenge_participants
  for each row execute function private.on_participant_notify();

-- Výzva: start (všem přijatým kromě toho, kdo start spustil) a výsledek.
create function private.on_challenge_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid;
  v_team  numeric;
begin
  if old.status = 'pending' and new.status = 'active' then
    -- duel spouští přijetí soupeře, skupinu zakladatel
    v_actor := coalesce(auth.uid(), new.creator_id);
    insert into public.notifications (user_id, kind, actor_id, challenge_id, payload)
    select cp.user_id, 'challenge_started', v_actor, new.id,
           jsonb_strip_nulls(jsonb_build_object('type', new.type, 'start_date', new.start_date,
                                                'duration_days', new.duration_days, 'stake', new.stake))
    from public.challenge_participants cp
    where cp.challenge_id = new.id and cp.status = 'accepted' and cp.user_id is distinct from v_actor;

  elsif old.status = 'active' and new.status = 'finished' then
    -- výsledky už zapsal finalize_challenge (před změnou stavu)
    if new.type = 'team_goal' then
      select avg(score) into v_team from public.challenge_day_scores where challenge_id = new.id;
      insert into public.notifications (user_id, kind, challenge_id, payload)
      select cp.user_id, 'challenge_result', new.id,
             jsonb_build_object('type', new.type, 'result', cp.result,
                                'my_avg', round(coalesce(v_team, 0), 1), 'target_score', new.target_score)
      from public.challenge_participants cp
      where cp.challenge_id = new.id and cp.status = 'accepted' and cp.result is not null;
    else
      -- soupeř v textu: vítěz → nejlepší poražený, poražený → vítěz, remíza → druhý z remízy
      insert into public.notifications (user_id, kind, actor_id, challenge_id, payload)
      select me.user_id, 'challenge_result', o.user_id, new.id,
             jsonb_build_object('type', new.type, 'result', me.result,
                                'my_avg', me.final_avg, 'other_avg', o.final_avg, 'other_result', o.result,
                                'souls', case when me.result = 'win'
                                              then (select count(*) from public.challenge_participants l
                                                    where l.challenge_id = new.id and l.result = 'loss') end)
      from public.challenge_participants me
      cross join lateral (
        select x.user_id, x.final_avg, x.result from public.challenge_participants x
        where x.challenge_id = new.id and x.status = 'accepted' and x.user_id <> me.user_id
          and (me.result <> 'draw' or x.result = 'draw')
        order by (x.result = 'win') desc, x.final_avg desc nulls last, x.user_id
        limit 1
      ) o
      where me.challenge_id = new.id and me.status = 'accepted' and me.result is not null;
    end if;
  end if;
  return null;
end;
$$;
create trigger challenges_notify after update of status on public.challenges
  for each row execute function private.on_challenge_notify();

-- Dluh označený jako splacený → věřiteli.
create function private.on_debt_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.settled_at is null and new.settled_at is not null then
    insert into public.notifications (user_id, kind, actor_id, challenge_id, payload)
    values (new.creditor_id, 'debt_settled', new.debtor_id, new.challenge_id,
            jsonb_build_object('stake', new.stake));
  end if;
  return null;
end;
$$;
create trigger debts_notify after update of settled_at on public.debts
  for each row execute function private.on_debt_notify();

-- Nový odznak (i opakovaný – „Zase.“). Proklik na kartu noci nebo výzvu.
create function private.on_achievement_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications (user_id, kind, post_id, challenge_id, payload)
  values (new.user_id, 'achievement',
          (select id from public.posts where night_id = new.night_id),
          new.challenge_id,
          jsonb_build_object('code', new.code,
                             'times', (select count(*) from public.user_achievements
                                       where user_id = new.user_id and code = new.code)));
  return null;
end;
$$;
create trigger user_achievements_notify after insert on public.user_achievements
  for each row execute function private.on_achievement_notify();

-- Ranní karta je venku. Jen čerstvé noci (dnes / včera místního času) –
-- zpětné dohrání starších nocí nespamuje.
create function private.on_post_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.kind <> 'night' then return null; end if;
  insert into public.notifications (user_id, kind, post_id)
  select new.user_id, 'night_ready', new.id
  from public.nights ni join public.profiles p on p.id = ni.user_id
  where ni.id = new.night_id
    and ni.night_date >= (now() at time zone p.timezone)::date - 1
  on conflict do nothing;
  return null;
end;
$$;
create trigger posts_notify after insert on public.posts
  for each row execute function private.on_post_notify();

-- =====================================================================
-- Plánované notifikace (pg_cron, každou hodinu) a úklid
-- =====================================================================

-- „Zítra konec“: ve 20:00 místního času hráče, den před posledním dnem výzvy.
-- Průběžný průměr = dny od startu do dneška, chybějící noc = 0.
create function private.notify_challenges_ending(p_now timestamptz default now())
returns int language plpgsql security definer set search_path = '' as $$
declare
  n int;
begin
  with due as (
    select c.id, c.type, c.start_date, c.end_date, c.target_score, cp.user_id
    from public.challenges c
    join public.challenge_participants cp on cp.challenge_id = c.id and cp.status = 'accepted'
    join public.profiles p on p.id = cp.user_id
    where c.status = 'active'
      and (p_now at time zone p.timezone)::date = c.end_date - 1
      and extract(hour from p_now at time zone p.timezone) = 20
  ), avgs as (
    select d.id, d.user_id,
           coalesce((select sum(s.score) from public.challenge_day_scores s
                     where s.challenge_id = d.id and s.user_id = d.user_id
                       and s.day between d.start_date and d.end_date - 1), 0)::numeric
             / greatest(d.end_date - d.start_date, 1) as avg
    from (select distinct id, start_date, end_date, user_id
          from public.challenges c2
          join public.challenge_participants cp2 on cp2.challenge_id = c2.id and cp2.status = 'accepted'
          where c2.id in (select id from due)) d
  ), facts as (
    select due.user_id, due.id,
           case when due.type = 'team_goal' then
             jsonb_build_object('mode', 'team', 'target_score', due.target_score,
                                'avg', round((select avg(a.avg) from avgs a where a.id = due.id), 1))
           else (
             select jsonb_build_object(
                      'mode', case when diff > 0 then 'lead' when diff < 0 then 'trail' else 'tie' end,
                      'diff', diff)
             from (select round(me.avg - (select max(o.avg) from avgs o
                                          where o.id = due.id and o.user_id <> due.user_id), 1) as diff
                   from avgs me where me.id = due.id and me.user_id = due.user_id) x)
           end as payload
    from due
  )
  insert into public.notifications (user_id, kind, challenge_id, payload)
  select user_id, 'challenge_ending', id, payload from facts where payload is not null
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Pondělní recap v 9:00 místního času, jen když minulý týden byla aspoň 1 noc.
create function private.notify_weekly_recaps(p_now timestamptz default now())
returns int language plpgsql security definer set search_path = '' as $$
declare
  n int;
begin
  insert into public.notifications (user_id, kind, payload)
  select x.id, 'weekly_recap',
         jsonb_build_object('week_start', x.ws, 'nights', count(ni.id), 'avg_score', round(avg(ni.score)))
  from (select p.id, date_trunc('week', p_now at time zone p.timezone)::date - 7 as ws
        from public.profiles p
        where extract(isodow from p_now at time zone p.timezone) = 1
          and extract(hour from p_now at time zone p.timezone) = 9) x
  join public.nights ni on ni.user_id = x.id and ni.night_date between x.ws and x.ws + 6 and ni.score is not null
  group by x.id, x.ws
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end;
$$;

create function private.notification_jobs()
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.notify_challenges_ending();
  perform private.notify_weekly_recaps();
end;
$$;

-- Úklid: notifikace starší 30 dní (reakce se posouvají s každou novou).
create function private.cleanup_notifications(p_days int default 30)
returns int language plpgsql security definer set search_path = '' as $$
declare
  n int;
begin
  delete from public.notifications where created_at < now() - make_interval(days => p_days);
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke execute on function
  private.sync_reaction_notification(uuid, boolean),
  private.on_reaction_notify(),
  private.on_comment_notify(),
  private.on_friendship_notify(),
  private.on_participant_notify(),
  private.on_challenge_notify(),
  private.on_debt_notify(),
  private.on_achievement_notify(),
  private.on_post_notify(),
  private.notify_challenges_ending(timestamptz),
  private.notify_weekly_recaps(timestamptz),
  private.notification_jobs(),
  private.cleanup_notifications(int)
from public, anon, authenticated;

-- Samostatná úloha (ne uvnitř hourly_jobs), ať ji nepřepíše jiná migrace
-- s novou verzí hourly_jobs. :07 – po uzavírání výzev v :05.
select cron.schedule('notification-jobs', '7 * * * *', $$select private.notification_jobs()$$);
select cron.schedule('notifications-cleanup', '20 3 * * *', $$select private.cleanup_notifications()$$);
