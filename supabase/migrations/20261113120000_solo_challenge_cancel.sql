-- Všichni proti všem: když si ostatní hráči smazali účet, jediný zbylý „vyhrál“
-- (pozvánka, První ovečka) bez poraženého. Souboj / všichni proti všem s méně než
-- 2 přijatými se při uzávěrce zruší – nikdo nic nezíská ani neztratí.
-- (Rozjetý souboj po smazání soupeře řeší kontumace v delete_my_account, #37.)

create or replace function private.finalize_challenge(p_challenge uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  c          public.challenges;
  v_top      numeric;
  v_ntop     int;
  v_second   numeric;
  v_winner   uuid;
  v_wins     int;
  v_souls    int;
  v_new      int;
  v_run      int := 0;
  v_nemesis  uuid;
  r          record;
begin
  select * into c from public.challenges where id = p_challenge and status = 'active' for update skip locked;
  if not found then return; end if;

  -- 0) souboj / všichni proti všem bez soupeře (ostatní si smazali účet) → zrušit
  if c.type <> 'team_goal' and (select count(*) from public.challenge_participants
                                where challenge_id = c.id and status = 'accepted') < 2 then
    update public.challenges set status = 'cancelled' where id = c.id;
    return;
  end if;

  -- 1) skóre z nocí, které se do výzvy nepropsaly, a nuly za chybějící noci
  insert into public.challenge_day_scores (challenge_id, user_id, day, score, night_id)
  select c.id, p.user_id, n.night_date, n.score, n.id
  from public.challenge_participants p
  join public.nights n on n.user_id = p.user_id
  where p.challenge_id = c.id and p.status = 'accepted' and n.score is not null
    and n.night_date between c.start_date and c.end_date
  on conflict do nothing;

  insert into public.challenge_day_scores (challenge_id, user_id, day, score)
  select c.id, p.user_id, d::date, 0
  from public.challenge_participants p
  cross join generate_series(c.start_date, c.end_date, interval '1 day') d
  where p.challenge_id = c.id and p.status = 'accepted'
  on conflict do nothing;

  perform private.award(x.user_id, 'forgot_watch', null, c.id)
  from (select distinct user_id from public.challenge_day_scores
        where challenge_id = c.id and night_id is null) x;

  -- 2) průměry a vyhrané dny (den vyhrává jen jasně nejvyšší skóre)
  update public.challenge_participants p
  set final_avg = s.avg_score, days_won = s.won
  from (
    select d.user_id,
           round(avg(d.score), 2) as avg_score,
           count(*) filter (where d.score > coalesce(
             (select max(o.score) from public.challenge_day_scores o
              where o.challenge_id = d.challenge_id and o.day = d.day and o.user_id <> d.user_id), -1)) as won
    from public.challenge_day_scores d
    where d.challenge_id = c.id
    group by d.user_id
  ) s
  where p.challenge_id = c.id and p.user_id = s.user_id and p.status = 'accepted';

  -- 3) výsledky
  if c.type = 'team_goal' then
    update public.challenge_participants
    set result = case when (select avg(score) from public.challenge_day_scores where challenge_id = c.id)
                           >= c.target_score then 'win'::public.challenge_result
                      else 'loss'::public.challenge_result end
    where challenge_id = c.id and status = 'accepted';
  else
    select max(final_avg) into v_top
    from public.challenge_participants where challenge_id = c.id and status = 'accepted';
    select count(*) into v_ntop
    from public.challenge_participants where challenge_id = c.id and status = 'accepted' and final_avg = v_top;

    update public.challenge_participants
    set result = case when final_avg < v_top then 'loss'::public.challenge_result
                      when v_ntop = 1 then 'win'::public.challenge_result
                      else 'draw'::public.challenge_result end
    where challenge_id = c.id and status = 'accepted';
  end if;

  update public.challenges set status = 'finished', finalized_at = now() where id = c.id;
  insert into public.posts (kind, challenge_id) values ('challenge_result', c.id) on conflict do nothing;

  -- 4) jasný vítěz (duel / všichni proti všem): dluhy, pozvánka, achievementy
  if c.type = 'team_goal' or v_ntop <> 1 then return; end if;

  select user_id into v_winner from public.challenge_participants where challenge_id = c.id and result = 'win';

  if c.stake is not null then
    insert into public.debts (challenge_id, debtor_id, creditor_id, stake)
    select c.id, user_id, v_winner, c.stake
    from public.challenge_participants where challenge_id = c.id and result = 'loss';
  end if;

  update public.profiles set invites_available = invites_available + 1 where id = v_winner;

  select count(*) into v_wins
  from public.challenge_participants cp join public.challenges x on x.id = cp.challenge_id
  where cp.user_id = v_winner and cp.result = 'win' and x.status = 'finished' and x.type <> 'team_goal';
  if v_wins = 1 then perform private.award(v_winner, 'first_soul', null, c.id); end if;

  select count(*) into v_souls from public.souls where winner_id = v_winner;
  select count(*) into v_new from public.challenge_participants where challenge_id = c.id and result = 'loss';
  if v_souls / 10 > (v_souls - v_new) / 10 then
    perform private.award(v_winner, 'collector', null, c.id);
  end if;

  for r in
    select cp.result from public.challenge_participants cp join public.challenges x on x.id = cp.challenge_id
    where cp.user_id = v_winner and cp.status = 'accepted' and x.status = 'finished' and x.type <> 'team_goal'
    order by x.end_date desc, x.finalized_at desc
  loop
    exit when r.result <> 'win';
    v_run := v_run + 1;
  end loop;
  if v_run > 0 and v_run % 5 = 0 then perform private.award(v_winner, 'undefeated', null, c.id); end if;

  -- Odplata: porazil jsi toho, kdo tě naposledy porazil
  select w.user_id into v_nemesis
  from public.challenge_participants me
  join public.challenges x on x.id = me.challenge_id
  join public.challenge_participants w on w.challenge_id = x.id and w.result = 'win'
  where me.user_id = v_winner and me.result = 'loss' and x.status = 'finished'
    and x.type <> 'team_goal' and x.id <> c.id
  order by x.end_date desc, x.finalized_at desc
  limit 1;
  if v_nemesis is not null and exists (
    select 1 from public.challenge_participants
    where challenge_id = c.id and user_id = v_nemesis and result = 'loss'
  ) then
    perform private.award(v_winner, 'revenge', null, c.id);
  end if;

  select max(final_avg) into v_second from public.challenge_participants where challenge_id = c.id and result = 'loss';
  if v_top - v_second < 1 then perform private.award(v_winner, 'by_a_hair', null, c.id); end if;
end;
$$;
