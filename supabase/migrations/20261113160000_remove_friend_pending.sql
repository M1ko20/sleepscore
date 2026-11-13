-- Odebrání z přátel nechávalo čekající souboj / pozvánku do skupinové výzvy:
-- bývalý kamarád ji pořád mohl přijmout a výzva se rozjela mezi ne-přáteli
-- („Výzvy jen mezi přáteli“). Teď stejně jako při blokování: čekající souboj
-- mezi námi se zruší, pozvánka do čekající skupinové výzvy toho druhého propadne.
-- Rozjeté výzvy doběhnou.

create or replace function public.remove_friend(p_user uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
begin
  delete from public.friendships
  where user_a = least(v_me, p_user) and user_b = greatest(v_me, p_user);

  update public.challenges c set status = 'cancelled'
  where c.status = 'pending' and c.type = 'duel'
    and exists (select 1 from public.challenge_participants cp
                where cp.challenge_id = c.id and cp.user_id = v_me)
    and exists (select 1 from public.challenge_participants cp
                where cp.challenge_id = c.id and cp.user_id = p_user);

  update public.challenge_participants cp
  set status = 'declined', responded_at = now()
  from public.challenges c
  where c.id = cp.challenge_id and c.status = 'pending' and c.type <> 'duel'
    and cp.status <> 'declined'
    and ((c.creator_id = v_me and cp.user_id = p_user)
      or (c.creator_id = p_user and cp.user_id = v_me));
end;
$$;
