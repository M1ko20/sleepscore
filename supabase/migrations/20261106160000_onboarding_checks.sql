-- Kontroly pro onboarding (jen přihlášení – anon nesmí nic, aby nešlo hádat kódy bez účtu).

-- Platí kód pozvánky? Nevrací, kdo pozval.
create function public.check_invite(p_code text)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.invites
    where code = upper(trim(p_code)) and redeemed_by is null
  );
$$;

-- Je přezdívka volná a ve správném formátu? (profiles cizích lidí přes RLS vidět nejsou)
create function public.username_available(p_username text)
returns boolean
language sql stable security definer set search_path = '' as $$
  select lower(p_username) ~ '^[a-z0-9_.]{3,20}$'
     and not exists (select 1 from public.profiles where username = lower(p_username));
$$;

revoke execute on function public.check_invite(text), public.username_available(text) from public, anon;
grant execute on function public.check_invite(text), public.username_available(text) to authenticated;
