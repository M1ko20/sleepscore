-- Noci podle data noci, ne podle data importu.
--
-- 1) Feed: karty nocí se řadily podle posts.created_at (kdy se noc nahrála).
--    Když někdo nahrál víc starých nocí najednou (první synchronizace, zpětné
--    nahrání), vyskočily všechny nahoru. Teď se řadí podle nights.night_date
--    (a konce spánku). Začíná se dál od mě a přátel; z každého se vezme jen
--    posledních p_limit nocí přes unikátní index nights (user_id, night_date).
--
-- 2) Profil: noci jednoho uživatele za rozsah dní (kalendář po měsících).
--    Security invoker → cizí noci vidí jen přátelé (RLS can_view_post / nights),
--    blok, nahlášení a skrytí platí stejně jako ve feedu.

create or replace function public.feed_night_posts(p_limit int default 30)
returns setof public.posts
language sql stable security invoker set search_path = '' as $$
  with authors as (
    select auth.uid() as id
    union
    select case when f.user_a = auth.uid() then f.user_b else f.user_a end
    from public.friendships f
    where (f.user_a = auth.uid() or f.user_b = auth.uid()) and f.status = 'accepted'
  ),
  picked as (
    select x.* from authors a
    cross join lateral (
      select p.id, n.night_date, n.sleep_end
      from public.nights n
      join public.posts p on p.night_id = n.id and p.kind = 'night'
      where n.user_id = a.id
      order by n.night_date desc
      limit least(greatest(p_limit, 1), 100)
    ) x
  )
  select p.* from picked k
  join public.posts p on p.id = k.id
  order by k.night_date desc, k.sleep_end desc, p.id desc
  limit least(greatest(p_limit, 1), 100);
$$;

-- Noci uživatele mezi p_from a p_to (včetně), od nejnovější. Max. 62 (dva měsíce).
create function public.user_night_posts(p_user uuid, p_from date, p_to date)
returns setof public.posts
language sql stable security invoker set search_path = '' as $$
  select p.* from public.nights n
  join public.posts p on p.night_id = n.id and p.kind = 'night'
  where n.user_id = p_user and n.night_date between p_from and p_to
  order by n.night_date desc
  limit 62;
$$;

revoke execute on function public.user_night_posts(uuid, date, date) from public, anon;
grant execute on function public.user_night_posts(uuid, date, date) to authenticated;
