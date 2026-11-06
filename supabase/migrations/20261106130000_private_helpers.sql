-- Pomocné funkce pro RLS přesunuty do schématu `private`, které není
-- vystavené v API (dřív šlo přes /rpc/are_friends zjistit, jestli jsou
-- přátelé dva libovolní lidé). Politiky odkazují na funkce přes OID,
-- takže je přesun nerozbije; těla funkcí, která je volají jménem,
-- přepisujeme níže.

create schema private;
grant usage on schema private to authenticated;

alter function public.is_member()                 set schema private;
alter function public.are_friends(uuid, uuid)     set schema private;
alter function public.can_view_challenge(uuid)    set schema private;
alter function public.can_view_post(uuid)         set schema private;
alter function public.is_friend_folder(text)      set schema private;

create or replace function private.can_view_challenge(p_challenge uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.challenge_participants cp
    where cp.challenge_id = p_challenge
      and cp.status <> 'declined'
      and private.are_friends(auth.uid(), cp.user_id)
  );
$$;

create or replace function private.can_view_post(p_post uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.posts p
    where p.id = p_post
      and (
        (p.kind = 'night' and private.are_friends(auth.uid(), p.user_id))
        or (p.kind = 'challenge_result' and private.can_view_challenge(p.challenge_id))
      )
  );
$$;

create or replace function private.is_friend_folder(p_folder text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  return private.are_friends(auth.uid(), p_folder::uuid);
exception when invalid_text_representation then
  return false;
end;
$$;

revoke execute on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;

-- RPC funkce, které helpery volají jménem
create or replace function public.send_friend_request(p_user uuid)
returns public.friendship_status
language plpgsql security definer set search_path = '' as $$
declare
  v_row public.friendships;
begin
  if not private.is_member() then raise exception 'not a member'; end if;
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

create or replace function public.create_challenge(
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
  if not private.is_member() then raise exception 'not a member'; end if;
  p_opponents := array(select distinct u from unnest(p_opponents) u where u <> auth.uid());

  if p_type = 'duel' and cardinality(p_opponents) <> 1 then
    raise exception 'duel needs exactly one opponent';
  elsif p_type <> 'duel' and cardinality(p_opponents) < 2 then
    raise exception 'group challenge needs at least two invited friends';
  end if;

  foreach v_opp in array p_opponents loop
    if not private.are_friends(auth.uid(), v_opp) then
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

alter function public.touch_updated_at() set search_path = '';
