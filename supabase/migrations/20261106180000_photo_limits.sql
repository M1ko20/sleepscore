-- Fotky: limity na serveru (telefon zmenšuje, tohle je pojistka proti obejití appky).
-- Profilovka 256 px ≈ 30 kB, fotka karty ≤ 200 kB → strop s rezervou.
update storage.buckets
set file_size_limit = 150 * 1024, allowed_mime_types = array['image/jpeg']
where id = 'avatars';

update storage.buckets
set file_size_limit = 400 * 1024, allowed_mime_types = array['image/jpeg']
where id = 'night-photos';

-- Cesta musí vést do vlastní složky – jinak by šlo „půjčit“ si cizí fotku
-- (čtení fotek karet se řídí složkou = vlastníkem).
alter table public.profiles
  add constraint profiles_avatar_path_own
  check (avatar_path is null or avatar_path like id::text || '/%');

alter table public.posts
  add constraint posts_photo_path_own
  check (photo_path is null or photo_path like user_id::text || '/%');
