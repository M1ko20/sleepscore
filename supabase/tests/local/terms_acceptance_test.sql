-- Souhlas s podmínkami (#20): stav, souhlas, RLS, redeem_invite bez souhlasu, nová verze, export.
-- Spouští run.sh.
\set ON_ERROR_STOP 1

create function public.t_ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAIL: %', msg; end if;
  raise notice 'ok  %', msg;
end;
$$;
create function public.t_err(p_sql text, p_expect text, msg text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAIL: % (nespadlo)', msg;
exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if position(p_expect in sqlerrm) = 0 then
    raise exception 'FAIL: % (čekal jsem "%", přišlo "%")', msg, p_expect, sqlerrm;
  end if;
  raise notice 'ok  %', msg;
end;
$$;
grant execute on function public.t_ok(boolean, text), public.t_err(text, text, text) to authenticated;

-- A je člen a pozve B. B je přihlášený bez profilu.
insert into auth.users (id) values
  ('00000000-0000-0000-0000-00000000000a'),
  ('00000000-0000-0000-0000-00000000000b');
insert into public.profiles (id, username, display_name) values
  ('00000000-0000-0000-0000-00000000000a', 'adam', 'Adam');
insert into public.user_stats (user_id) values ('00000000-0000-0000-0000-00000000000a');
insert into public.invites (code, inviter_id) values ('TERMS123', '00000000-0000-0000-0000-00000000000a');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);

select t_ok((public.my_terms_status() ->> 'accepted')::boolean = false, 'nový účet: nesouhlasil');
select t_ok(public.my_terms_status() ->> 'version' = '2026-11-06', 'verze = datum účinnosti');
select t_err($$select public.redeem_invite('TERMS123', 'bara', 'Bára')$$, 'terms not accepted',
             'bez souhlasu profil nevznikne');
select t_err($$insert into public.terms_acceptances (user_id, version)
               values ('00000000-0000-0000-0000-00000000000b', '2026-11-06')$$, 'permission denied',
             'přímý zápis nejde');

select t_ok((public.accept_terms() ->> 'accepted')::boolean, 'souhlas uložen');
select t_ok((select count(*) from public.terms_acceptances) = 1, 'opakovaný souhlas nic nezdvojí') from (select public.accept_terms()) _;
select t_ok((public.redeem_invite('TERMS123', 'bara', 'Bára')).username = 'bara', 's souhlasem profil vznikne');

-- A (beta, bez záznamu) souhlas nemá a nevidí cizí souhlasy
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select t_ok((public.my_terms_status() ->> 'accepted')::boolean = false, 'stávající uživatel bez souhlasu');
select t_ok((select count(*) from public.terms_acceptances) = 0, 'RLS: cizí souhlas nevidím');

-- Nová verze podmínek → B znovu nesouhlasil
reset role;
create or replace function private.terms_version()
returns text language sql immutable set search_path = '' as $$ select '2027-01-01'; $$;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select t_ok((public.my_terms_status() ->> 'accepted')::boolean = false, 'nová verze: znovu souhlas');
select t_ok((public.accept_terms() ->> 'version') = '2027-01-01', 'souhlas s novou verzí');
select t_ok(jsonb_array_length(public.export_my_data() -> 'terms_acceptances') = 2, 'export: obě verze');

-- anon nic
reset role;
set role anon;
select t_err($$select public.accept_terms()$$, 'permission denied', 'anon nesmí accept_terms');
reset role;
