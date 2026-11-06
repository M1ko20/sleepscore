-- Testovací výzvy pro dev účty @adam, @jakub a @karolina (jen dev data!).
--   supabase db query --remote --yes -f supabase/tests/seed_dev_challenges.sql
-- Předpoklad: noci ze seed_dev.py. Smaže předchozí výzvy těchto dvou účtů.
do $$
declare
  a uuid := (select id from public.profiles where username = 'adam');
  j uuid := (select id from public.profiles where username = 'jakub');
  k uuid := (select id from public.profiles where username = 'karolina');
  today date := (now() at time zone 'Europe/Prague')::date;
  c_done uuid; c_run uuid; c_pend uuid; c_ffa uuid; c_ffa_run uuid; c_team uuid;
begin
  -- Odznaky za staré testovací výzvy pryč (po smazání výzvy by zůstaly s challenge_id null
  -- a nové udělení by narazilo na unikátní klíč).
  delete from public.user_achievements ua
  where ua.user_id in (a, j, k)
    and (ua.challenge_id in (select id from public.challenges where creator_id in (a, j, k))
         or (ua.challenge_id is null and ua.night_id is null
             and ua.code in ('first_soul', 'collector', 'undefeated', 'revenge', 'by_a_hair', 'forgot_watch')));
  delete from public.challenges where creator_id in (a, j, k);

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

  if k is not null then
    -- 4) Uzavřená všichni proti všem (Karolína zakládala), poražení platí snídani.
    insert into public.challenges (type, creator_id, stake, duration_days, start_date, end_date, status)
    values ('free_for_all', k, 'poražení platí snídani', 7, today - 7, today - 1, 'active') returning id into c_ffa;
    insert into public.challenge_participants (challenge_id, user_id, status, responded_at)
    values (c_ffa, k, 'accepted', now()), (c_ffa, a, 'accepted', now()), (c_ffa, j, 'accepted', now());
    perform private.finalize_challenge(c_ffa);

    -- 5) Běžící všichni proti všem (Adam zakládal), od předevčírka.
    insert into public.challenges (type, creator_id, stake, duration_days, start_date, end_date, status)
    values ('free_for_all', a, 'kdo prohraje, peče', 7, today - 2, today + 4, 'active') returning id into c_ffa_run;
    insert into public.challenge_participants (challenge_id, user_id, status, responded_at)
    values (c_ffa_run, a, 'accepted', now()), (c_ffa_run, j, 'accepted', now()), (c_ffa_run, k, 'accepted', now());
    insert into public.challenge_day_scores (challenge_id, user_id, day, score, night_id)
    select c_ffa_run, n.user_id, n.night_date, n.score, n.id
    from public.nights n
    where n.user_id in (a, j, k) and n.night_date between today - 2 and today and n.score is not null;

    -- 6) Běžící společný cíl (Karolína), cíl průměr 85.
    insert into public.challenges (type, creator_id, duration_days, target_score, start_date, end_date, status)
    values ('team_goal', k, 7, 85, today - 1, today + 5, 'active') returning id into c_team;
    insert into public.challenge_participants (challenge_id, user_id, status, responded_at)
    values (c_team, k, 'accepted', now()), (c_team, a, 'accepted', now()), (c_team, j, 'accepted', now());
    insert into public.challenge_day_scores (challenge_id, user_id, day, score, night_id)
    select c_team, n.user_id, n.night_date, n.score, n.id
    from public.nights n
    where n.user_id in (a, j, k) and n.night_date between today - 1 and today and n.score is not null;
  end if;
end $$;

select c.status, c.stake, c.start_date, c.end_date, p.username, cp.final_avg, cp.days_won, cp.result
from public.challenges c
join public.challenge_participants cp on cp.challenge_id = c.id
join public.profiles p on p.id = cp.user_id
order by c.created_at, p.username;
