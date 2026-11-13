-- Odebrání z přátel ruší čekající výzvy mezi námi. Spouští run.sh.
\set ON_ERROR_STOP 1

create function pg_temp.ok(msg text, got anyelement, want anyelement) returns void language plpgsql as $$
begin
  if got is distinct from want then raise exception 'FAIL: % (čekal jsem %, přišlo %)', msg, want, got; end if;
  raise notice 'ok  %', msg;
end;
$$;
create function pg_temp.u(x text) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-00000000000' || x)::uuid $$;
create function pg_temp.ch(x text) returns uuid language sql as $$
  select ('30000000-0000-0000-0000-00000000000' || x)::uuid $$;

insert into auth.users (id) select pg_temp.u(x) from unnest(array['a','b','c']) x;
insert into public.profiles (id, username, display_name)
select pg_temp.u(x), 'user' || x, 'User ' || x from unnest(array['a','b','c']) x;
insert into public.friendships (user_a, user_b, requested_by, status, accepted_at) values
  (pg_temp.u('a'), pg_temp.u('b'), pg_temp.u('a'), 'accepted', now()),
  (pg_temp.u('a'), pg_temp.u('c'), pg_temp.u('a'), 'accepted', now());

-- 1: čekající souboj a → b, 2: čekající skupina b (zakladatel) s a, c, 3: běžící souboj a × b
insert into public.challenges (id, type, creator_id, duration_days, start_date, end_date, status) values
  (pg_temp.ch('1'), 'duel', pg_temp.u('a'), 7, null, null, 'pending'),
  (pg_temp.ch('2'), 'free_for_all', pg_temp.u('b'), 7, null, null, 'pending'),
  (pg_temp.ch('3'), 'duel', pg_temp.u('a'), 7, current_date - 1, current_date + 5, 'active');
insert into public.challenge_participants (challenge_id, user_id, status) values
  (pg_temp.ch('1'), pg_temp.u('a'), 'accepted'), (pg_temp.ch('1'), pg_temp.u('b'), 'invited'),
  (pg_temp.ch('2'), pg_temp.u('b'), 'accepted'), (pg_temp.ch('2'), pg_temp.u('a'), 'invited'), (pg_temp.ch('2'), pg_temp.u('c'), 'invited'),
  (pg_temp.ch('3'), pg_temp.u('a'), 'accepted'), (pg_temp.ch('3'), pg_temp.u('b'), 'accepted');

select set_config('request.jwt.claim.sub', pg_temp.u('a')::text, false);
set role authenticated;
select public.remove_friend(pg_temp.u('b'));
reset role;

select pg_temp.ok('přátelství pryč', (select count(*)::int from public.friendships where pg_temp.u('b') in (user_a, user_b)), 0);
select pg_temp.ok('čekající souboj zrušen', (select status::text from public.challenges where id = pg_temp.ch('1')), 'cancelled');
select pg_temp.ok('pozvánka do skupiny propadla', (select status::text from public.challenge_participants
  where challenge_id = pg_temp.ch('2') and user_id = pg_temp.u('a')), 'declined');
select pg_temp.ok('ostatní pozvaní dál', (select status::text from public.challenge_participants
  where challenge_id = pg_temp.ch('2') and user_id = pg_temp.u('c')), 'invited');
select pg_temp.ok('běžící souboj doběhne', (select status::text from public.challenges where id = pg_temp.ch('3')), 'active');
select pg_temp.ok('jiné přátelství zůstává', (select count(*)::int from public.friendships where pg_temp.u('c') in (user_a, user_b)), 1);
