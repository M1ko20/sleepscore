-- =====================================================================
-- Sleep app – počáteční schéma (V1)
--
-- Princip:
--   * Klient (iOS) ČTE přes RLS, ale citlivé věci (noci, skóre, výzvy,
--     přátelství, pozvánky, dluhy) nezapisuje přímo. Zápisy jdou buď přes
--     RPC funkce níže (security definer, kontrolují pravidla), nebo přes
--     Edge Functions se service role (ingest spánku, výpočet skóre,
--     uzavírání výzev, achievementy).
--   * Přímo z klienta jde jen: úprava vlastní karty (název, komentář, fotka),
--     tagy vlastní noci, komentáře, reakce, push tokeny, vlastní profil.
--   * Uživatel bez řádku v `profiles` (přihlásil se Applem, ale neuplatnil
--     pozvánku) nevidí nic.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Enumy
-- ---------------------------------------------------------------------
create type public.friendship_status as enum ('pending', 'accepted');
create type public.challenge_type as enum ('duel', 'free_for_all', 'team_goal');
create type public.challenge_status as enum ('pending', 'active', 'finished', 'cancelled');
create type public.participant_status as enum ('invited', 'accepted', 'declined');
create type public.challenge_result as enum ('win', 'loss', 'draw');
create type public.post_kind as enum ('night', 'challenge_result');
create type public.reaction_kind as enum ('sleeper', 'zombie', 'beer', 'coffee', 'crown');

-- ---------------------------------------------------------------------
-- Profily a pozvánky
-- ---------------------------------------------------------------------
create table public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  username          text not null,
  display_name      text not null check (char_length(display_name) between 1 and 40),
  avatar_path       text,
  timezone          text not null default 'Europe/Prague',
  invites_available int  not null default 3 check (invites_available >= 0),
  invited_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  constraint username_format check (username ~ '^[a-z0-9_.]{3,20}$')
);
create unique index profiles_username_key on public.profiles (username);

create table public.invites (
  code        text primary key,
  inviter_id  uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  redeemed_by uuid unique references public.profiles (id) on delete set null,
  redeemed_at timestamptz
);
create index invites_inviter_idx on public.invites (inviter_id);

-- ---------------------------------------------------------------------
-- Přátelství (jeden řádek na dvojici, user_a < user_b)
-- ---------------------------------------------------------------------
create table public.friendships (
  user_a       uuid not null references public.profiles (id) on delete cascade,
  user_b       uuid not null references public.profiles (id) on delete cascade,
  requested_by uuid not null references public.profiles (id) on delete cascade,
  status       public.friendship_status not null default 'pending',
  created_at   timestamptz not null default now(),
  accepted_at  timestamptz,
  primary key (user_a, user_b),
  check (user_a < user_b),
  check (requested_by in (user_a, user_b))
);
create index friendships_user_b_idx on public.friendships (user_b);

-- ---------------------------------------------------------------------
-- Spánek
-- ---------------------------------------------------------------------
-- Jedna hlavní noc na uživatele a den (den = datum konce spánku, pokud
-- skončil do 14:00 místního času; přiřazení dělá ingest funkce).
create table public.nights (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  night_date      date not null,
  sleep_start     timestamptz not null,
  sleep_end       timestamptz not null,
  total_sleep_min int not null check (total_sleep_min >= 0),
  awake_min       int not null default 0,
  core_min        int not null default 0,
  deep_min        int not null default 0,
  rem_min         int not null default 0,
  wake_count      int not null default 0,
  hr_avg          numeric(5, 1),
  hr_min          smallint,
  score           smallint check (score between 0 and 100),
  score_breakdown jsonb,          -- {"duration":..,"stages":..,"interruptions":..,"regularity":..,"heart_rate":..}
  score_version   smallint,
  source_name     text,           -- zdroj z HealthKitu (např. "Garmin Connect")
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (user_id, night_date),
  check (sleep_end > sleep_start)
);
create index nights_user_date_idx on public.nights (user_id, night_date desc);

-- Surová data pro přepočet skóre a hypnogram. JSON místo řádku na vzorek:
-- tep je ~400 vzorků/noc, řádek na vzorek by rychle vyčerpal Free tarif.
create table public.night_raw (
  night_id    uuid primary key references public.nights (id) on delete cascade,
  segments    jsonb not null,   -- [{"start":"..","end":"..","stage":"deep","hk_uuid":".."}]
  heart_rate  jsonb,            -- [["2026-11-06T01:02:00Z", 52], ...]
  received_at timestamptz not null default now()
);

create table public.tags (
  slug  text primary key,
  label text not null,
  emoji text,
  sort  smallint not null default 0
);

create table public.night_tags (
  night_id uuid not null references public.nights (id) on delete cascade,
  tag      text not null references public.tags (slug),
  primary key (night_id, tag)
);

-- ---------------------------------------------------------------------
-- Výzvy (souboje)
-- ---------------------------------------------------------------------
create table public.challenges (
  id            uuid primary key default gen_random_uuid(),
  type          public.challenge_type not null,
  creator_id    uuid not null references public.profiles (id) on delete cascade,
  stake         text check (char_length(stake) <= 200),
  duration_days int  not null check (duration_days >= 7),
  target_score  smallint check (target_score between 1 and 100),
  start_date    date,           -- nastaví se při startu
  end_date      date,           -- start_date + duration_days - 1
  status        public.challenge_status not null default 'pending',
  created_at    timestamptz not null default now(),
  finalized_at  timestamptz,
  check ((type = 'team_goal') = (target_score is not null)),
  check (end_date is null or end_date = start_date + duration_days - 1)
);
create index challenges_status_end_idx on public.challenges (status, end_date);

create table public.challenge_participants (
  challenge_id uuid not null references public.challenges (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  status       public.participant_status not null default 'invited',
  responded_at timestamptz,
  final_avg    numeric(5, 2),
  days_won     int,
  result       public.challenge_result,
  primary key (challenge_id, user_id)
);
create index challenge_participants_user_idx on public.challenge_participants (user_id);

-- Denní skóre ve výzvě. Zapisuje server; po uzavření výzvy se nemění.
-- Chybějící noc = score 0 a night_id null.
create table public.challenge_day_scores (
  challenge_id uuid not null references public.challenges (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  day          date not null,
  score        smallint not null check (score between 0 and 100),
  night_id     uuid references public.nights (id) on delete set null,
  primary key (challenge_id, user_id, day)
);

create table public.debts (
  id           uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.challenges (id) on delete cascade,
  debtor_id    uuid not null references public.profiles (id) on delete cascade,
  creditor_id  uuid not null references public.profiles (id) on delete cascade,
  stake        text not null,
  created_at   timestamptz not null default now(),
  settled_at   timestamptz,
  check (debtor_id <> creditor_id)
);
create index debts_debtor_idx on public.debts (debtor_id);
create index debts_creditor_idx on public.debts (creditor_id);

-- ---------------------------------------------------------------------
-- Feed: karty nocí a výsledkové karty výzev
-- ---------------------------------------------------------------------
create table public.posts (
  id           uuid primary key default gen_random_uuid(),
  kind         public.post_kind not null,
  user_id      uuid references public.profiles (id) on delete cascade,   -- autor (u výsledku výzvy null)
  night_id     uuid unique references public.nights (id) on delete cascade,
  challenge_id uuid unique references public.challenges (id) on delete cascade,
  title        text check (char_length(title) <= 80),
  body         text check (char_length(body) <= 1000),
  photo_path   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (
    (kind = 'night' and night_id is not null and user_id is not null and challenge_id is null)
    or (kind = 'challenge_result' and challenge_id is not null and night_id is null)
  )
);
create index posts_created_idx on public.posts (created_at desc);
create index posts_user_idx on public.posts (user_id, created_at desc);

create table public.comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.posts (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index comments_post_idx on public.comments (post_id, created_at);

-- Jedna reakce od člověka na kartu (změna = upsert).
create table public.reactions (
  post_id    uuid not null references public.posts (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  kind       public.reaction_kind not null,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

-- ---------------------------------------------------------------------
-- Achievementy, série, push
-- ---------------------------------------------------------------------
create table public.achievements (
  code        text primary key,
  name        text not null,
  description text not null,
  category    text not null,
  sort        smallint not null default 0
);

-- Opakovatelné: více řádků se stejným kódem. Unikátnost brání jen
-- dvojímu udělení za tutéž noc / výzvu.
create table public.user_achievements (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  code         text not null references public.achievements (code),
  earned_at    timestamptz not null default now(),
  night_id     uuid references public.nights (id) on delete set null,
  challenge_id uuid references public.challenges (id) on delete set null,
  unique nulls not distinct (user_id, code, night_id, challenge_id)
);
create index user_achievements_user_idx on public.user_achievements (user_id, earned_at desc);

create table public.user_stats (
  user_id          uuid primary key references public.profiles (id) on delete cascade,
  current_streak   int  not null default 0,
  best_streak      int  not null default 0,
  last_streak_date date,
  freeze_used_week date,   -- pondělí týdne, kdy byl naposledy použit streak freeze
  updated_at       timestamptz not null default now()
);

create table public.push_tokens (
  token      text primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  updated_at timestamptz not null default now()
);

-- =====================================================================
-- Pomocné funkce pro RLS
-- =====================================================================
create function public.is_member()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid());
$$;

create function public.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select a = b or exists (
    select 1 from public.friendships f
    where f.user_a = least(a, b) and f.user_b = greatest(a, b) and f.status = 'accepted'
  );
$$;

-- Výzvu vidí účastníci a přátelé účastníků (výsledek jde do feedu).
create function public.can_view_challenge(p_challenge uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.challenge_participants cp
    where cp.challenge_id = p_challenge
      and cp.status <> 'declined'
      and public.are_friends(auth.uid(), cp.user_id)
  );
$$;

create function public.can_view_post(p_post uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.posts p
    where p.id = p_post
      and (
        (p.kind = 'night' and public.are_friends(auth.uid(), p.user_id))
        or (p.kind = 'challenge_result' and public.can_view_challenge(p.challenge_id))
      )
  );
$$;

-- =====================================================================
-- RLS
-- =====================================================================
alter table public.profiles               enable row level security;
alter table public.invites                enable row level security;
alter table public.friendships            enable row level security;
alter table public.nights                 enable row level security;
alter table public.night_raw              enable row level security;
alter table public.tags                   enable row level security;
alter table public.night_tags             enable row level security;
alter table public.challenges             enable row level security;
alter table public.challenge_participants enable row level security;
alter table public.challenge_day_scores   enable row level security;
alter table public.debts                  enable row level security;
alter table public.posts                  enable row level security;
alter table public.comments               enable row level security;
alter table public.reactions              enable row level security;
alter table public.achievements           enable row level security;
alter table public.user_achievements      enable row level security;
alter table public.user_stats             enable row level security;
alter table public.push_tokens            enable row level security;

-- Anonymní role nemá přístup nikam.
revoke all on all tables in schema public from anon;

-- Přímé zápisy z klienta jen tam, kde to dává smysl; jinak RPC / service role.
revoke insert, update, delete on all tables in schema public from authenticated;
grant update (display_name, avatar_path, timezone) on public.profiles to authenticated;
grant update (title, body, photo_path) on public.posts to authenticated;
grant insert, delete on public.night_tags to authenticated;
grant insert, delete on public.comments to authenticated;
grant insert, update, delete on public.reactions to authenticated;
grant insert, update, delete on public.push_tokens to authenticated;

-- profiles: základní profil (přezdívka, jméno, fotka) vidí každý člen –
-- kvůli hledání přátel. Statistiky a noci jsou chráněné zvlášť.
create policy profiles_select on public.profiles for select to authenticated
  using (public.is_member());
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy invites_select on public.invites for select to authenticated
  using (inviter_id = auth.uid() or redeemed_by = auth.uid());

create policy friendships_select on public.friendships for select to authenticated
  using (auth.uid() in (user_a, user_b));

create policy nights_select on public.nights for select to authenticated
  using (public.are_friends(auth.uid(), user_id));
create policy night_raw_select on public.night_raw for select to authenticated
  using (exists (select 1 from public.nights n
                 where n.id = night_id and public.are_friends(auth.uid(), n.user_id)));

create policy tags_select on public.tags for select to authenticated using (true);

create policy night_tags_select on public.night_tags for select to authenticated
  using (exists (select 1 from public.nights n
                 where n.id = night_id and public.are_friends(auth.uid(), n.user_id)));
create policy night_tags_insert on public.night_tags for insert to authenticated
  with check (exists (select 1 from public.nights n where n.id = night_id and n.user_id = auth.uid()));
create policy night_tags_delete on public.night_tags for delete to authenticated
  using (exists (select 1 from public.nights n where n.id = night_id and n.user_id = auth.uid()));

create policy challenges_select on public.challenges for select to authenticated
  using (public.can_view_challenge(id));
create policy challenge_participants_select on public.challenge_participants for select to authenticated
  using (public.can_view_challenge(challenge_id));
create policy challenge_day_scores_select on public.challenge_day_scores for select to authenticated
  using (public.can_view_challenge(challenge_id));

create policy debts_select on public.debts for select to authenticated
  using (auth.uid() in (debtor_id, creditor_id));

create policy posts_select on public.posts for select to authenticated
  using (public.can_view_post(id));
create policy posts_update on public.posts for update to authenticated
  using (kind = 'night' and user_id = auth.uid())
  with check (kind = 'night' and user_id = auth.uid());

create policy comments_select on public.comments for select to authenticated
  using (public.can_view_post(post_id));
create policy comments_insert on public.comments for insert to authenticated
  with check (user_id = auth.uid() and public.can_view_post(post_id));
create policy comments_delete on public.comments for delete to authenticated
  using (user_id = auth.uid()
         or exists (select 1 from public.posts p where p.id = post_id and p.user_id = auth.uid()));

create policy reactions_select on public.reactions for select to authenticated
  using (public.can_view_post(post_id));
create policy reactions_insert on public.reactions for insert to authenticated
  with check (user_id = auth.uid() and public.can_view_post(post_id));
create policy reactions_update on public.reactions for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy reactions_delete on public.reactions for delete to authenticated
  using (user_id = auth.uid());

create policy achievements_select on public.achievements for select to authenticated using (true);
create policy user_achievements_select on public.user_achievements for select to authenticated
  using (public.are_friends(auth.uid(), user_id));
create policy user_stats_select on public.user_stats for select to authenticated
  using (public.are_friends(auth.uid(), user_id));

create policy push_tokens_all on public.push_tokens for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- =====================================================================
-- Odvozené pohledy: MMA bilance, duše, vzájemná bilance
-- (security_invoker => platí RLS volajícího)
-- =====================================================================

-- MMA bilance: všechny typy výzev. U společného cíle mají všichni
-- výhru (cíl splněn) nebo prohru (nesplněn); duše se ale nebere.
create view public.mma_records with (security_invoker = true) as
select cp.user_id,
       count(*) filter (where cp.result = 'win')  as wins,
       count(*) filter (where cp.result = 'loss') as losses,
       count(*) filter (where cp.result = 'draw') as draws
from public.challenge_participants cp
join public.challenges c on c.id = cp.challenge_id
where c.status = 'finished' and cp.result is not null
group by cp.user_id;

-- Duše: vítěz bere duši každého poraženého (duel i všichni proti všem).
create view public.souls with (security_invoker = true) as
select c.id         as challenge_id,
       w.user_id    as winner_id,
       l.user_id    as loser_id,
       c.end_date,
       w.final_avg  as winner_avg,
       l.final_avg  as loser_avg
from public.challenges c
join public.challenge_participants w on w.challenge_id = c.id and w.result = 'win'
join public.challenge_participants l on l.challenge_id = c.id and l.result = 'loss'
where c.status = 'finished' and c.type <> 'team_goal';

-- Vzájemná bilance dvojice (z pohledu user_id proti opponent_id).
-- Společný cíl se nepočítá – tam hráči hrají spolu, ne proti sobě.
create view public.head_to_head with (security_invoker = true) as
select me.user_id,
       opp.user_id as opponent_id,
       count(*) filter (where me.final_avg >  opp.final_avg) as wins,
       count(*) filter (where me.final_avg <  opp.final_avg) as losses,
       count(*) filter (where me.final_avg =  opp.final_avg) as draws
from public.challenges c
join public.challenge_participants me  on me.challenge_id  = c.id and me.status  = 'accepted'
join public.challenge_participants opp on opp.challenge_id = c.id and opp.status = 'accepted'
                                       and opp.user_id <> me.user_id
where c.status = 'finished' and c.type <> 'team_goal'
group by me.user_id, opp.user_id;

revoke all on public.mma_records, public.souls, public.head_to_head from anon;
grant select on public.mma_records, public.souls, public.head_to_head to authenticated;

-- =====================================================================
-- RPC funkce (zápisy z klienta s kontrolou pravidel)
-- =====================================================================

-- Registrace: po Sign in with Apple uplatní pozvánku a založí profil.
-- Pozvaný a pozvaný-kdo-zval se rovnou stanou přáteli.
create function public.redeem_invite(p_code text, p_username text, p_display_name text)
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

-- Vytvoří pozvánku (spotřebuje jednu z dostupných).
create function public.create_invite()
returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_code text;
begin
  update public.profiles set invites_available = invites_available - 1
  where id = auth.uid() and invites_available > 0;
  if not found then raise exception 'no invites available'; end if;

  loop
    -- 8 znaků bez zaměnitelných (0/O, 1/I/L)
    select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), '')
      into v_code from generate_series(1, 8);
    exit when not exists (select 1 from public.invites where code = v_code);
  end loop;

  insert into public.invites (code, inviter_id) values (v_code, auth.uid());
  return v_code;
end;
$$;

-- Žádost o přátelství. Když už protistrana žádost poslala, rovnou přijme.
create function public.send_friend_request(p_user uuid)
returns public.friendship_status
language plpgsql security definer set search_path = '' as $$
declare
  v_row public.friendships;
begin
  if not public.is_member() then raise exception 'not a member'; end if;
  if p_user = auth.uid() then raise exception 'cannot befriend yourself'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then
    raise exception 'user not found';
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

-- Přijetí / odmítnutí žádosti (odmítnutí řádek smaže).
create function public.respond_friend_request(p_user uuid, p_accept boolean)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_accept then
    update public.friendships set status = 'accepted', accepted_at = now()
    where user_a = least(auth.uid(), p_user) and user_b = greatest(auth.uid(), p_user)
      and status = 'pending' and requested_by = p_user;
  else
    delete from public.friendships
    where user_a = least(auth.uid(), p_user) and user_b = greatest(auth.uid(), p_user)
      and status = 'pending' and requested_by = p_user;
  end if;
  if not found then raise exception 'no pending request'; end if;
end;
$$;

-- Zrušení přátelství nebo stažení vlastní žádosti.
create function public.remove_friend(p_user uuid)
returns void
language sql security definer set search_path = '' as $$
  delete from public.friendships
  where user_a = least(auth.uid(), p_user) and user_b = greatest(auth.uid(), p_user);
$$;

-- Založení výzvy. Soupeři musí být přátelé zakladatele.
-- Duel: přesně 1 soupeř, startuje další den po přijetí.
-- Skupina: 2+ pozvaných, startuje zakladatel přes start_challenge.
create function public.create_challenge(
  p_type          public.challenge_type,
  p_opponents     uuid[],
  p_duration_days int,
  p_stake         text default null,
  p_target_score  smallint default null
)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id  uuid;
  v_opp uuid;
begin
  if not public.is_member() then raise exception 'not a member'; end if;
  p_opponents := array(select distinct u from unnest(p_opponents) u where u <> auth.uid());

  if p_type = 'duel' and cardinality(p_opponents) <> 1 then
    raise exception 'duel needs exactly one opponent';
  elsif p_type <> 'duel' and cardinality(p_opponents) < 2 then
    raise exception 'group challenge needs at least two invited friends';
  end if;

  foreach v_opp in array p_opponents loop
    if not public.are_friends(auth.uid(), v_opp) then
      raise exception 'opponent % is not a friend', v_opp;
    end if;
  end loop;

  insert into public.challenges (type, creator_id, stake, duration_days, target_score)
  values (p_type, auth.uid(), nullif(trim(p_stake), ''), p_duration_days,
          case when p_type = 'team_goal' then p_target_score end)
  returning id into v_id;

  insert into public.challenge_participants (challenge_id, user_id, status, responded_at)
  values (v_id, auth.uid(), 'accepted', now());
  insert into public.challenge_participants (challenge_id, user_id)
  select v_id, unnest(p_opponents);

  return v_id;
end;
$$;

-- Interní: aktivuje výzvu od zítřka (podle časového pásma zakladatele).
create function public.activate_challenge(p_challenge uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_tz text;
begin
  select p.timezone into v_tz
  from public.challenges c join public.profiles p on p.id = c.creator_id
  where c.id = p_challenge;

  update public.challenges
  set status = 'active',
      start_date = (now() at time zone v_tz)::date + 1,
      end_date   = (now() at time zone v_tz)::date + duration_days
  where id = p_challenge and status = 'pending';

  -- Kdo nestihl odpovědět, vypadává.
  update public.challenge_participants set status = 'declined', responded_at = now()
  where challenge_id = p_challenge and status = 'invited';
end;
$$;
revoke execute on function public.activate_challenge(uuid) from public, anon, authenticated;

create function public.respond_challenge(p_challenge uuid, p_accept boolean)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_type public.challenge_type;
begin
  update public.challenge_participants cp
  set status = case when p_accept then 'accepted'::public.participant_status
                    else 'declined'::public.participant_status end,
      responded_at = now()
  from public.challenges c
  where cp.challenge_id = p_challenge and cp.user_id = auth.uid()
    and cp.status = 'invited' and c.id = cp.challenge_id and c.status = 'pending'
  returning c.type into v_type;
  if not found then raise exception 'no pending invitation'; end if;

  if v_type = 'duel' then
    if p_accept then
      perform public.activate_challenge(p_challenge);
    else
      update public.challenges set status = 'cancelled' where id = p_challenge;
    end if;
  end if;
end;
$$;

-- Start skupinové výzvy zakladatelem (aspoň 3 přijatí včetně zakladatele).
create function public.start_challenge(p_challenge uuid)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.challenges
                 where id = p_challenge and creator_id = auth.uid()
                   and status = 'pending' and type <> 'duel') then
    raise exception 'not allowed';
  end if;
  if (select count(*) from public.challenge_participants
      where challenge_id = p_challenge and status = 'accepted') < 3 then
    raise exception 'need at least 3 accepted participants';
  end if;
  perform public.activate_challenge(p_challenge);
end;
$$;

create function public.cancel_challenge(p_challenge uuid)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.challenges set status = 'cancelled'
  where id = p_challenge and creator_id = auth.uid() and status = 'pending';
  if not found then raise exception 'not allowed'; end if;
end;
$$;

-- Splacení dluhu označuje dlužník.
create function public.settle_debt(p_debt uuid)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.debts set settled_at = now()
  where id = p_debt and debtor_id = auth.uid() and settled_at is null;
  if not found then raise exception 'not allowed'; end if;
end;
$$;

-- updated_at u karet
create function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger posts_touch before update on public.posts
  for each row execute function public.touch_updated_at();
create trigger nights_touch before update on public.nights
  for each row execute function public.touch_updated_at();

-- Funkce jsou volatelné jen přihlášenými (ne anon).
revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.is_member(), public.are_friends(uuid, uuid),
  public.can_view_challenge(uuid), public.can_view_post(uuid),
  public.redeem_invite(text, text, text), public.create_invite(),
  public.send_friend_request(uuid), public.respond_friend_request(uuid, boolean),
  public.remove_friend(uuid),
  public.create_challenge(public.challenge_type, uuid[], int, text, smallint),
  public.respond_challenge(uuid, boolean), public.start_challenge(uuid),
  public.cancel_challenge(uuid), public.settle_debt(uuid)
to authenticated;

-- =====================================================================
-- Storage: profilovky a fotky ke kartám. Cesta = "<user_id>/<soubor>".
-- =====================================================================
insert into storage.buckets (id, name, public) values
  ('avatars', 'avatars', false),
  ('night-photos', 'night-photos', false);

create policy storage_avatars_read on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and public.is_member());
-- Složka nemusí být platné UUID (cizí/poškozená cesta) – pak false, ne chyba.
create function public.is_friend_folder(p_folder text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  return public.are_friends(auth.uid(), p_folder::uuid);
exception when invalid_text_representation then
  return false;
end;
$$;
revoke execute on function public.is_friend_folder(text) from public, anon;
grant execute on function public.is_friend_folder(text) to authenticated;

create policy storage_night_photos_read on storage.objects for select to authenticated
  using (bucket_id = 'night-photos'
         and public.is_friend_folder((storage.foldername(name))[1]));
create policy storage_own_insert on storage.objects for insert to authenticated
  with check (bucket_id in ('avatars', 'night-photos')
              and (storage.foldername(name))[1] = auth.uid()::text);
create policy storage_own_update on storage.objects for update to authenticated
  using (bucket_id in ('avatars', 'night-photos')
         and (storage.foldername(name))[1] = auth.uid()::text);
create policy storage_own_delete on storage.objects for delete to authenticated
  using (bucket_id in ('avatars', 'night-photos')
         and (storage.foldername(name))[1] = auth.uid()::text);
