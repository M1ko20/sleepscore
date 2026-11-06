-- Testovací výzvy pro dev účty @adam a @jakub (jen dev data!).
--   supabase db query --remote --yes -f supabase/tests/seed_dev_challenges.sql
-- Předpoklad: noci ze seed_dev.py. Smaže předchozí výzvy těchto dvou účtů.
do $$
declare
  a uuid := (select id from public.profiles where username = 'adam');
  j uuid := (select id from public.profiles where username = 'jakub');
  today date := (now() at time zone 'Europe/Prague')::date;
  c_done uuid; c_run uuid; c_pend uuid;
begin
  delete from public.challenges where creator_id in (a, j);

  -- 1) Uzavřená: 7 dní končící včera, prohraný platí pivo.
  insert into public.challenges (type, creator_id, stake, duration_days, start_date, end_date, status)
  values ('duel', a, 'prohraný platí pivo', 7, today - 7, today - 1, 'active') returning id into c_done;
  insert into public.challenge_participants (challenge_id, user_id, status, responded_at)
  values (c_done, a, 'accepted', now()), (c_done, j, 'accepted', now());
  perform private.finalize_challenge(c_done);

  -- 2) Běžící: začala před 3 dny, 7 dní, sázka kafe.
  insert into public.challenges (type, creator_id, stake, duration_days, start_date, end_date, status)
  values ('duel', j, 'kafe', 7, today - 3, today + 3, 'active') returning id into c_run;
  insert into public.challenge_participants (challenge_id, user_id, status, responded_at)
  values (c_run, j, 'accepted', now()), (c_run, a, 'accepted', now());
  insert into public.challenge_day_scores (challenge_id, user_id, day, score, night_id)
  select c_run, n.user_id, n.night_date, n.score, n.id
  from public.nights n
  where n.user_id in (a, j) and n.night_date between today - 3 and today and n.score is not null;

  -- 3) Čekající pozvánka: Jakub vyzval Adama.
  insert into public.challenges (type, creator_id, stake, duration_days)
  values ('duel', j, 'večeře', 14) returning id into c_pend;
  insert into public.challenge_participants (challenge_id, user_id, status, responded_at)
  values (c_pend, j, 'accepted', now());
  insert into public.challenge_participants (challenge_id, user_id) values (c_pend, a);
end $$;

select c.status, c.stake, c.start_date, c.end_date, p.username, cp.final_avg, cp.days_won, cp.result
from public.challenges c
join public.challenge_participants cp on cp.challenge_id = c.id
join public.profiles p on p.id = cp.user_id
order by c.created_at, p.username;
