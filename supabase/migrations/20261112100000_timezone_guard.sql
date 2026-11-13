-- #33: Neplatné časové pásmo v profilu shodilo celé hodinové úlohy
-- (`time zone "…" not recognized` → rollback uzavírání výzev, sérií, notifikací pro všechny).
-- Pásmo musí být v pg_timezone_names; klient ho přímo nemění (nastavuje ho ingest).

create function private.is_valid_timezone(p_tz text)
returns boolean language sql stable set search_path = '' as $$
  select p_tz is not null and exists (select 1 from pg_catalog.pg_timezone_names where name = p_tz);
$$;

-- Úklid případných už uložených neplatných hodnot.
update public.profiles set timezone = 'Europe/Prague' where not private.is_valid_timezone(timezone);
update public.challenges set timezone = 'Europe/Prague' where not private.is_valid_timezone(timezone);

create function private.guard_profile_timezone()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_valid_timezone(new.timezone) then
    raise exception 'invalid timezone' using errcode = '22023';
  end if;
  return new;
end;
$$;
create trigger profiles_guard_timezone before insert or update of timezone on public.profiles
  for each row execute function private.guard_profile_timezone();

-- Výzva bere pásmo zakladatele; neplatné/chybějící → Praha.
create or replace function private.challenge_set_timezone()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.timezone is null then
    select p.timezone into new.timezone from public.profiles p where p.id = new.creator_id;
  end if;
  if not private.is_valid_timezone(new.timezone) then
    new.timezone := 'Europe/Prague';
  end if;
  return new;
end;
$$;

revoke update (timezone) on public.profiles from authenticated;

revoke execute on function private.is_valid_timezone(text), private.guard_profile_timezone()
from public, anon, authenticated;
