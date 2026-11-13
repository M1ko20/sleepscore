-- Výzva zrušená, protože soupeř smazal účet (čekající souboj, výzva, která ještě
-- nezačala), už nezmizí ze seznamu bez vysvětlení: zbylým přijde notifikace
-- „Soupeř smazal účet. Souboj se ruší.“ (druh challenge_result, payload cancelled).

create or replace function private.settle_orphaned_challenge(p_challenge uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  c      public.challenges;
  v_left int;
  v_all  int;
  v_last uuid;
  v_why  text;
begin
  -- zámek výzvy: finalize zamyká stejný řádek, takže se nepotkají
  select * into c from public.challenges
  where id = p_challenge and status in ('pending', 'active') for update;
  if not found then return; end if;

  select count(*) filter (where status = 'accepted'), count(*),
         (array_agg(user_id) filter (where status = 'accepted'))[1]
  into v_left, v_all, v_last
  from public.challenge_participants where challenge_id = c.id;

  if c.status = 'pending' then
    if (c.type = 'duel' and v_all < 2) or v_left = 0 then v_why := 'cancel'; end if;
  elsif v_left = 0 then
    v_why := 'cancel';
  elsif v_left = 1 and c.type <> 'team_goal' then
    v_why := case when c.start_date > (now() at time zone c.timezone)::date then 'cancel'   -- nikdo nehrál
                  else 'forfeit' end;
  end if;

  if v_why = 'cancel' then
    update public.challenges set status = 'cancelled' where id = c.id;
    -- ať výzva nezmizí ze seznamu bez vysvětlení
    insert into public.notifications (user_id, kind, challenge_id, payload)
    select cp.user_id, 'challenge_result', c.id,
           jsonb_build_object('type', c.type, 'cancelled', true)
    from public.challenge_participants cp
    where cp.challenge_id = c.id and cp.status in ('accepted', 'invited');
    return;
  end if;

  if v_why = 'forfeit' then
    update public.challenge_participants p
    set result = 'win',
        final_avg = (select round(avg(d.score), 2) from public.challenge_day_scores d
                     where d.challenge_id = c.id and d.user_id = p.user_id)
    where p.challenge_id = c.id and p.user_id = v_last;
    -- on_challenge_notify nenajde soupeře (už není), notifikaci píšeme sami
    update public.challenges set status = 'finished', finalized_at = now(), forfeit = true where id = c.id;
    insert into public.notifications (user_id, kind, challenge_id, payload)
    values (v_last, 'challenge_result', c.id,
            jsonb_build_object('type', c.type, 'result', 'win', 'forfeit', true,
                               'my_avg', (select final_avg from public.challenge_participants
                                          where challenge_id = c.id and user_id = v_last)));
    update public.profiles set invites_available = invites_available + 1 where id = v_last;
  end if;
end;
$$;

do $$
declare
  v_def text := pg_get_functiondef('public.notification_text(public.notifications)'::regprocedure);
  v_old text := $q$    if p ? 'forfeit' then$q$;
  v_new text := $q$    if p ? 'cancelled' then
      return case when p ->> 'type' = 'duel' then 'Soupeř smazal účet. Souboj se ruší.'
                  else 'Ostatní smazali účet. Výzva se ruší.' end;
    end if;
    if p ? 'forfeit' then$q$;
begin
  if position(v_old in v_def) = 0 then raise exception 'notification_text: forfeit branch not found'; end if;
  execute replace(v_def, v_old, v_new);
end;
$$;
