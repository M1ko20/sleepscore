-- GDPR: smazání účtu a export dat.
-- Výzvy přežijí smazání zakladatele (ostatním zůstanou výhry, duše, bilance),
-- proto si výzva drží vlastní časové pásmo místo čtení ze zakladatelova profilu.

alter table public.challenges add column timezone text;
update public.challenges c set timezone = p.timezone
from public.profiles p where p.id = c.creator_id and c.timezone is null;
update public.challenges set timezone = 'Europe/Prague' where timezone is null;
alter table public.challenges alter column timezone set not null;

alter table public.challenges alter column creator_id drop not null;
alter table public.challenges drop constraint challenges_creator_id_fkey;
alter table public.challenges add constraint challenges_creator_id_fkey
  foreign key (creator_id) references public.profiles (id) on delete set null;

-- Pásmo se doplní při založení ze zakladatele (create_challenge se nemusí měnit).
create or replace function private.challenge_set_timezone()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.timezone is null then
    select p.timezone into new.timezone from public.profiles p where p.id = new.creator_id;
    new.timezone := coalesce(new.timezone, 'Europe/Prague');
  end if;
  return new;
end;
$$;
create trigger challenges_set_timezone before insert on public.challenges
  for each row execute function private.challenge_set_timezone();

create or replace function public.activate_challenge(p_challenge uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_tz text;
begin
  select c.timezone into v_tz from public.challenges c where c.id = p_challenge;

  update public.challenges
  set status = 'active',
      start_date = (now() at time zone v_tz)::date + 1,
      end_date   = (now() at time zone v_tz)::date + duration_days
  where id = p_challenge and status = 'pending';

  -- Kdo nestihl odpovědět, vypadává.
  update public.challenge_participants set status = 'declined', responded_at = now()
  where challenge_id = p_challenge and status = 'invited';
end;
$$;
revoke execute on function public.activate_challenge(uuid) from public, anon, authenticated;

create or replace function private.finalize_due_challenges()
returns int language plpgsql security definer set search_path = '' as $$
declare
  r record;
  n int := 0;
begin
  for r in
    select c.id from public.challenges c
    where c.status = 'active' and now() >= ((c.end_date + time '14:00') at time zone c.timezone)
  loop
    perform private.finalize_challenge(r.id);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------
-- Smazání účtu. Appka předtím smaže vlastní soubory ve Storage
-- (přímý DELETE ze storage.objects Supabase nepovoluje).
-- ---------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not authenticated'; end if;

  -- Neuzavřené souboje se mnou nemají bez soupeře smysl → zrušit.
  -- Skupinové běží dál beze mě (účastník zmizí kaskádou).
  update public.challenges c set status = 'cancelled'
  where c.status in ('pending', 'active') and c.type = 'duel'
    and exists (select 1 from public.challenge_participants cp
                where cp.challenge_id = c.id and cp.user_id = v_me);
  -- Moje čekající skupinové výzvy (ještě nikdo nehrál) → zrušit.
  update public.challenges set status = 'cancelled'
  where creator_id = v_me and status = 'pending';

  -- auth.users → kaskádou profiles a vše navázané (noci, karty, komentáře, reakce,
  -- přátelství, účasti, dluhy, odznaky, pozvánky, push tokeny).
  delete from auth.users where id = v_me;
end;
$$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- ---------------------------------------------------------------------
-- Export (právo na přístup / přenositelnost): všechna moje data jako JSON.
-- ---------------------------------------------------------------------
create or replace function public.export_my_data()
returns jsonb
language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'exported_at', now(),
    'profile', (select to_jsonb(p) from public.profiles p where p.id = auth.uid()),
    'stats', (select to_jsonb(s) from public.user_stats s where s.user_id = auth.uid()),
    'nights', coalesce((select jsonb_agg(to_jsonb(n) || jsonb_build_object(
                          'raw', (select to_jsonb(r) - 'night_id' from public.night_raw r where r.night_id = n.id),
                          'tags', (select coalesce(jsonb_agg(t.tag), '[]'::jsonb) from public.night_tags t where t.night_id = n.id))
                        order by n.night_date)
                        from public.nights n where n.user_id = auth.uid()), '[]'::jsonb),
    'posts', coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at)
                       from public.posts p where p.user_id = auth.uid()), '[]'::jsonb),
    'comments', coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at)
                          from public.comments c where c.user_id = auth.uid()), '[]'::jsonb),
    'reactions', coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at)
                           from public.reactions r where r.user_id = auth.uid()), '[]'::jsonb),
    'friendships', coalesce((select jsonb_agg(to_jsonb(f))
                             from public.friendships f where auth.uid() in (f.user_a, f.user_b)), '[]'::jsonb),
    'challenges', coalesce((select jsonb_agg(to_jsonb(c) || jsonb_build_object('me', to_jsonb(cp) - 'challenge_id'))
                            from public.challenge_participants cp join public.challenges c on c.id = cp.challenge_id
                            where cp.user_id = auth.uid()), '[]'::jsonb),
    'challenge_day_scores', coalesce((select jsonb_agg(to_jsonb(d) order by d.day)
                                      from public.challenge_day_scores d where d.user_id = auth.uid()), '[]'::jsonb),
    'debts', coalesce((select jsonb_agg(to_jsonb(d))
                       from public.debts d where auth.uid() in (d.debtor_id, d.creditor_id)), '[]'::jsonb),
    'achievements', coalesce((select jsonb_agg(to_jsonb(a) order by a.earned_at)
                              from public.user_achievements a where a.user_id = auth.uid()), '[]'::jsonb),
    'invites', coalesce((select jsonb_agg(to_jsonb(i))
                         from public.invites i where i.inviter_id = auth.uid()), '[]'::jsonb)
  );
$$;
revoke execute on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;
