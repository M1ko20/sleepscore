-- Po `seed_dev.py --history`: karty starých nocí dostanou created_at = konec spánku,
-- ať se ve feedu (řazený podle created_at) neobjeví nahoře. Jen dev data.
update public.posts p
set created_at = n.sleep_end
from public.nights n
where p.night_id = n.id
  and p.kind = 'night'
  and n.night_date < (now() at time zone 'Europe/Prague')::date - 7
  and p.created_at > n.sleep_end + interval '1 day';
