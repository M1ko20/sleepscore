-- Feed bez procházení celé tabulky karet.
--
-- Dřív appka četla `posts` seřazené podle created_at a RLS (can_view_post)
-- kontrolovala řádek po řádku, dokud jich nenašla dost. Kdo má málo aktivních
-- přátel, prošel celou tabulku; výsledky výzev (jich je málo) ji procházely
-- vždycky – lokálně ~1 s na 40 000 karet. Na Free tieru to žere CPU.
--
-- Teď se začíná od mě a mých přátel (index friendships) a z každého se vezme
-- jen posledních p_limit karet (index posts_user_idx). Funkce jsou security
-- invoker → RLS dál platí na každý vrácený řádek (blok, nahlášení, skrytí),
-- takže výsledek je stejný jako dřív, jen se nečte zbytek tabulky.

-- Karty nocí: já + přátelé, od nejnovější.
create function public.feed_night_posts(p_limit int default 30)
returns setof public.posts
language sql stable security invoker set search_path = '' as $$
  with authors as (
    select auth.uid() as id
    union
    select case when f.user_a = auth.uid() then f.user_b else f.user_a end
    from public.friendships f
    where (f.user_a = auth.uid() or f.user_b = auth.uid()) and f.status = 'accepted'
  )
  select p.* from authors a
  cross join lateral (
    select * from public.posts p
    where p.user_id = a.id and p.kind = 'night'
    order by p.created_at desc, p.id desc
    limit least(greatest(p_limit, 1), 100)
  ) p
  order by p.created_at desc, p.id desc
  limit least(greatest(p_limit, 1), 100);
$$;

-- Karty výsledků výzev, kterých se účastnil někdo z nás (stejně jako can_view_challenge).
create function public.feed_result_posts(p_limit int default 20)
returns setof public.posts
language sql stable security invoker set search_path = '' as $$
  with authors as (
    select auth.uid() as id
    union
    select case when f.user_a = auth.uid() then f.user_b else f.user_a end
    from public.friendships f
    where (f.user_a = auth.uid() or f.user_b = auth.uid()) and f.status = 'accepted'
  ),
  challenges as (
    select distinct cp.challenge_id
    from authors a
    join public.challenge_participants cp on cp.user_id = a.id and cp.status <> 'declined'
  )
  select p.* from challenges c
  cross join lateral (
    select * from public.posts p
    where p.challenge_id = c.challenge_id and p.kind = 'challenge_result'
  ) p
  order by p.created_at desc, p.id desc
  limit least(greatest(p_limit, 1), 100);
$$;

revoke execute on function public.feed_night_posts(int), public.feed_result_posts(int) from public, anon;
grant execute on function public.feed_night_posts(int), public.feed_result_posts(int) to authenticated;
