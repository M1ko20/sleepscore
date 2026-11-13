-- Výzva bez soupeře se řeší hned, když soupeř odejde (smazání účtu – i ručně adminem),
-- ne až při uzávěrce. Domluveno s Adamem 2026-11-13:
-- * Rozjetý souboj / všichni proti všem, kde zbyl jediný přijatý → kontumační výhra
--   zbylému (výhra do MMA, pozvánka navíc, notifikace). Ovečky a dluhy nejsou – poražení zmizeli.
-- * Ještě nezačala (start zítra) a zbyl jediný → zrušit.
-- * Nezbyl nikdo (i společný cíl) → zrušit.
-- * Čekající souboj, ze kterého kdokoliv zmizí → zrušit.
-- Dřív to v souboji řešil delete_my_account (#37) a ve všichni proti všem až finalize
-- (zrušení, zbylý hráč přišel o výhru). Teď jedno místo: trigger po smazání účastníka.

create or replace function private.settle_orphaned_challenge(p_challenge uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  c      public.challenges;
  v_left int;
  v_all  int;
  v_last uuid;
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
    if (c.type = 'duel' and v_all < 2) or v_left = 0 then
      update public.challenges set status = 'cancelled' where id = c.id;
    end if;
    return;
  end if;

  if v_left = 0 then
    update public.challenges set status = 'cancelled' where id = c.id;
  elsif v_left = 1 and c.type <> 'team_goal' then
    if c.start_date > (now() at time zone c.timezone)::date then
      update public.challenges set status = 'cancelled' where id = c.id;   -- nikdo nehrál
      return;
    end if;
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

create function private.on_participant_deleted()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.settle_orphaned_challenge(old.challenge_id);
  return null;
end;
$$;
create trigger challenge_participants_deleted after delete on public.challenge_participants
  for each row execute function private.on_participant_deleted();

-- Smazání účtu: výzvy zamknout předem (stejné pořadí zámků jako finalize: výzva → účastníci),
-- zbytek vyřeší trigger po kaskádovém smazání účasti.
create or replace function public.delete_my_account()
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not authenticated'; end if;

  perform 1 from public.challenges x
  where x.status in ('pending', 'active')
    and exists (select 1 from public.challenge_participants cp
                where cp.challenge_id = x.id and cp.user_id = v_me)
  order by x.id
  for update;

  -- Moje čekající skupinové výzvy (ještě nikdo nehrál) → zrušit.
  update public.challenges set status = 'cancelled'
  where creator_id = v_me and status = 'pending';

  -- auth.users → kaskádou profiles a vše navázané (noci, karty, komentáře, reakce,
  -- přátelství, účasti, dluhy, odznaky, pozvánky, push tokeny).
  delete from auth.users where id = v_me;
end;
$$;

-- Text notifikace: ve všichni proti všem odešli všichni ostatní.
do $$
declare
  v_def text := pg_get_functiondef('public.notification_text(public.notifications)'::regprocedure);
  v_old text := $q$return 'Soupeř smazal účet. Výhra kontumačně.';$q$;
  v_new text := $q$return case when p ->> 'type' = 'free_for_all' then 'Ostatní smazali účet. Výhra kontumačně.'
                  else 'Soupeř smazal účet. Výhra kontumačně.' end;$q$;
begin
  if position(v_old in v_def) = 0 then raise exception 'notification_text: forfeit text not found'; end if;
  execute replace(v_def, v_old, v_new);
end;
$$;

revoke execute on function private.settle_orphaned_challenge(uuid), private.on_participant_deleted()
  from public, anon, authenticated;

-- Výzvy, které už teď běží bez soupeře (vzniklé před touto migrací).
select private.settle_orphaned_challenge(c.id) from public.challenges c where c.status in ('pending', 'active');
