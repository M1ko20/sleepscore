-- #35: Výzva se uzavírá poslední den ve 14:00 (pásmo výzvy), cron ji ale finalizuje
-- až v :05 další hodiny. Mezitím ingest dál zapisoval denní skóre a finalizace
-- převzala i noci nahrané po uzávěrce → výsledek šel ještě ~hodinu změnit.
--
-- Pojistka v DB (ingest se nemění): po uzávěrce se denní skóre nezapíše ani nezmění.
-- Výjimka je finalizace samotná (doplňuje nuly a nepropsané noci) – ta pozná
-- příznak `bedrival.finalizing` a i tak vezme jen noci uložené před uzávěrkou.

create function private.guard_day_score_deadline()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  c          public.challenges;
  v_deadline timestamptz;
begin
  select * into c from public.challenges where id = new.challenge_id;
  if not found then return new; end if;   -- FK to stejně odmítne
  v_deadline := (c.end_date + time '14:00') at time zone c.timezone;

  if coalesce(current_setting('bedrival.finalizing', true), '') = 'on' then
    -- noc uložená po uzávěrce se nepočítá → finalizace za ten den doplní 0
    if new.night_id is not null and exists (
      select 1 from public.nights n where n.id = new.night_id and n.created_at >= v_deadline
    ) then
      return null;
    end if;
    return new;
  end if;

  if c.status <> 'active' or now() >= v_deadline then
    return null;   -- tiše přeskočit (ingest dál uloží noc i kartu)
  end if;
  return new;
end;
$$;
create trigger challenge_day_scores_deadline before insert or update on public.challenge_day_scores
  for each row execute function private.guard_day_score_deadline();

create or replace function private.finalize_due_challenges()
returns int language plpgsql security definer set search_path = '' as $$
declare
  r record;
  n int := 0;
begin
  perform set_config('bedrival.finalizing', 'on', true);
  for r in
    select c.id from public.challenges c
    where c.status = 'active' and now() >= ((c.end_date + time '14:00') at time zone c.timezone)
  loop
    perform private.finalize_challenge(r.id);
    n := n + 1;
  end loop;
  perform set_config('bedrival.finalizing', 'off', true);
  return n;
end;
$$;

revoke execute on function private.guard_day_score_deadline() from public, anon, authenticated;
