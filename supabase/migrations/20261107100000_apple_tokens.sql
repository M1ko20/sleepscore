-- Sign in with Apple: refresh token pro zneplatnění při smazání účtu (App Review 5.1.1(v)).
-- Zapisuje a čte jen Edge Function se service role (apple-token, delete-account).
-- Appka sem nevidí: RLS zapnuté bez politik + odebraná práva anon/authenticated.
-- Řádek zmizí kaskádou se smazáním auth.users (delete-account ho přečte předtím).

create table public.apple_tokens (
  user_id uuid primary key references auth.users (id) on delete cascade,
  refresh_token text not null,
  updated_at timestamptz not null default now()
);

alter table public.apple_tokens enable row level security;
revoke all on table public.apple_tokens from public, anon, authenticated;
grant select, insert, update, delete on table public.apple_tokens to service_role;

comment on table public.apple_tokens is
  'Apple refresh token (Sign in with Apple) – jen pro /auth/revoke při smazání účtu. Jen service role.';
