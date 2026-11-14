-- Tagy v2 (domluveno s Adamem 14. 11.): 4 tagy, které spánek kazí, a 4, které pomáhají.
-- Vyřazené tagy (kafe, večerní trénink, pozdní jídlo, dítě) mizí i ze starých nocí –
-- skuteční uživatelé zatím nejsou, jen testovací a review účty.
-- Nové odznaky: Scroll vyhrál, Nezničitelný, Zkouškové, Regenerace (za noc) a Detox (série).

-- =====================================================================
-- 1) Katalog tagů
-- =====================================================================
alter table public.tags add column positive boolean not null default false;

-- Mazání vyřazených tagů z nocí nesmí spouštět přepočet (týká se jen alkoholu, ten zůstává).
delete from public.night_tags where tag in ('late_coffee', 'evening_workout', 'late_meal', 'kid');
delete from public.tags where slug in ('late_coffee', 'evening_workout', 'late_meal', 'kid');

update public.tags set sort = 10 where slug = 'alcohol';
update public.tags set sort = 20 where slug = 'sick';
update public.tags set sort = 30 where slug = 'phone_in_bed';

insert into public.tags (slug, label, emoji, sort, positive) values
  ('studying',  'Učení',         '📚', 40,  false),
  ('workout',   'Trénink',       '🏋️', 110, true),
  ('no_phone',  'Bez telefonu',  '📵', 120, true),
  ('reading',   'Čtení',         '📖', 130, true),
  ('sauna',     'Sauna',         '🧖', 140, true);

-- =====================================================================
-- 2) Odznaky
-- =====================================================================
insert into public.achievements (code, name, description, category, sort) values
  ('scroll_won',  'Scroll vyhrál', 'tag telefon v posteli a sleep score pod 50',  'tags', 230),
  ('unbreakable', 'Nezničitelný',  'tag nemoc a sleep score 80 a víc',            'tags', 240),
  ('exam_season', 'Zkouškové',     'tag učení a méně než 6 hodin spánku',         'tags', 250),
  ('recovery',    'Regenerace',    'tag trénink a sleep score 85 a víc',          'tags', 260),
  ('detox',       'Detox',         '7 nocí v řadě s tagem bez telefonu',          'tags', 270);

-- Odznaky za jednu otagovanou noc (volá award_night_achievements → i reaward_night).
create or replace function private.award_tag_achievements(p_night uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  n      public.nights;
  v_tags text[];
begin
  select * into n from public.nights where id = p_night;
  if not found then return; end if;
  select coalesce(array_agg(tag), '{}') into v_tags from public.night_tags where night_id = p_night;
  if cardinality(v_tags) = 0 then return; end if;

  if 'alcohol' = any(v_tags) and n.score >= 85 then perform private.award(n.user_id, 'despite_it', p_night); end if;
  if 'alcohol' = any(v_tags) and n.score < 50 then perform private.award(n.user_id, 'beer_won', p_night); end if;
  if 'phone_in_bed' = any(v_tags) and n.score < 50 then perform private.award(n.user_id, 'scroll_won', p_night); end if;
  if 'sick' = any(v_tags) and n.score >= 80 then perform private.award(n.user_id, 'unbreakable', p_night); end if;
  if 'studying' = any(v_tags) and n.total_sleep_min < 360 then perform private.award(n.user_id, 'exam_season', p_night); end if;
  if 'workout' = any(v_tags) and n.score >= 85 then perform private.award(n.user_id, 'recovery', p_night); end if;
end;
$$;

-- Seznam odznaků za noc, které přepočet smaže a vyhodnotí znovu (+ nové tagové).
create or replace function private.reaward_night(p_night uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_codes constant text[] := array['coma', 'zombie', 'night_shift', 'didnt_move', 'deep_diver',
    'perfect_night', 'either_or', 'stolen_hour', 'new_year_survivor', 'despite_it', 'beer_won', 'swiss_watch',
    'scroll_won', 'unbreakable', 'exam_season', 'recovery'];
  v_user uuid;
  v_old  jsonb;
begin
  select user_id into v_user from public.nights where id = p_night;
  if not found then return; end if;

  select coalesce(jsonb_object_agg(code, earned_at), '{}'::jsonb) into v_old
  from public.user_achievements where night_id = p_night and code = any(v_codes);
  delete from public.user_achievements where night_id = p_night and code = any(v_codes);

  perform set_config('bedrival.reaward', v_old::text, true);
  perform private.award_night_achievements(p_night);
  perform set_config('bedrival.reaward', '', true);

  update public.user_achievements ua set earned_at = (v_old ->> ua.code)::timestamptz
  where ua.night_id = p_night and v_old ? ua.code;

  delete from public.notifications n
  where n.user_id = v_user and n.kind = 'achievement'
    and n.post_id = (select id from public.posts where night_id = p_night)
    and v_old ? (n.payload ->> 'code')
    and not exists (select 1 from public.user_achievements ua
                    where ua.night_id = p_night and ua.code = n.payload ->> 'code');
end;
$$;

-- Detox: každá 7. noc nepřerušené řady nocí s tagem „bez telefonu“ (7., 14., 21. …).
-- Tagy se doplňují zpětně a v libovolném pořadí → přepočítá se celá historie uživatele
-- (pár stovek nocí, mění se jen při změně tagu). Co zůstalo, si drží datum a nehlásí se znovu.
create function private.recompute_detox(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_old jsonb;
  r     record;
begin
  select coalesce(jsonb_object_agg(night_id::text, earned_at), '{}'::jsonb) into v_old
  from public.user_achievements where user_id = p_user and code = 'detox' and night_id is not null;
  delete from public.user_achievements where user_id = p_user and code = 'detox' and night_id is not null;

  for r in
    with tagged as (
      select n.id, n.night_date,
             n.night_date - (row_number() over (order by n.night_date))::int as grp
      from public.nights n
      where n.user_id = p_user
        and exists (select 1 from public.night_tags t where t.night_id = n.id and t.tag = 'no_phone')
    )
    select id, row_number() over (partition by grp order by night_date) as pos
    from tagged
  loop
    continue when r.pos % 7 <> 0;
    perform set_config('bedrival.reaward', case when v_old ? r.id::text then '{"detox": true}' else '' end, true);
    perform private.award(p_user, 'detox', r.id);
  end loop;
  perform set_config('bedrival.reaward', '', true);

  update public.user_achievements ua set earned_at = (v_old ->> ua.night_id::text)::timestamptz
  where ua.user_id = p_user and ua.code = 'detox' and v_old ? ua.night_id::text;

  delete from public.notifications n
  where n.user_id = p_user and n.kind = 'achievement' and n.payload ->> 'code' = 'detox'
    and not exists (select 1 from public.user_achievements ua
                    join public.posts p on p.night_id = ua.night_id
                    where ua.user_id = p_user and ua.code = 'detox' and p.id = n.post_id);
end;
$$;

-- Tag přidaný i odebraný → přepočet odznaků té noci (resp. Detoxu).
create or replace function private.on_night_tag()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_tag   text := coalesce(new.tag, old.tag);
  v_night uuid := coalesce(new.night_id, old.night_id);
  v_user  uuid;
begin
  if v_tag in ('alcohol', 'phone_in_bed', 'sick', 'studying', 'workout') then
    perform private.reaward_night(v_night);
  elsif v_tag = 'no_phone' then
    select user_id into v_user from public.nights where id = v_night;
    if found then perform private.recompute_detox(v_user); end if;
  end if;
  return null;
end;
$$;

revoke execute on function private.recompute_detox(uuid) from public, anon, authenticated;
