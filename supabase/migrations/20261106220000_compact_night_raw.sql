-- Zmenšení surových dat starých nocí (šetří místo na Free tieru).
-- Plná data drží 120 dní (výzvy, insighty 90 dní, případný přepočet skóre).
-- Starší noc: sousední úseky stejné fáze se slijí, hk_uuid zmizí (sloužilo jen
-- k nahrání), tep se zprůměruje do 5min oken. Hypnogram, Wrapped i export dál fungují;
-- průměr a minimum tepu jsou uložené v nights.

alter table public.night_raw add column compacted boolean not null default false;

create or replace function private.compact_segments(p jsonb)
returns jsonb language sql immutable set search_path = '' as $$
  with x as (
    select e->>'stage' as stage, (e->>'start')::timestamptz as s, (e->>'end')::timestamptz as e
    from jsonb_array_elements(coalesce(p, '[]'::jsonb)) e
  ), l as (
    select stage, s, e,
           case when stage is distinct from lag(stage) over w or s > lag(e) over w then 1 else 0 end as brk
    from x window w as (order by s, e)
  ), g as (
    select stage, s, e, sum(brk) over (order by s, e rows unbounded preceding) as grp from l
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'start', to_char(min_s at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
           'end',   to_char(max_e at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
           'stage', stage) order by min_s), '[]'::jsonb)
  from (select stage, min(s) as min_s, max(e) as max_e from g group by stage, grp) m;
$$;

create or replace function private.compact_heart_rate(p jsonb)
returns jsonb language sql immutable set search_path = '' as $$
  select case when p is null then null else coalesce((
    select jsonb_agg(jsonb_build_array(
             to_char(b at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'), bpm) order by b)
    from (
      select date_bin('5 minutes', (h->>0)::timestamptz, timestamptz '2000-01-01 00:00+00') as b,
             round(avg((h->>1)::numeric), 1) as bpm
      from jsonb_array_elements(p) h
      group by 1
    ) z), '[]'::jsonb) end;
$$;

create or replace function private.compact_old_night_raw(p_keep_days int default 120, p_limit int default 5000)
returns int language plpgsql security definer set search_path = '' as $$
declare
  n int;
begin
  update public.night_raw r
  set segments   = private.compact_segments(r.segments),
      heart_rate = private.compact_heart_rate(r.heart_rate),
      compacted  = true
  where r.night_id in (
    select r2.night_id from public.night_raw r2
    join public.nights ni on ni.id = r2.night_id
    where not r2.compacted and ni.night_date < current_date - p_keep_days
    limit p_limit);
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke execute on function private.compact_old_night_raw(int, int) from public, anon, authenticated;

-- denně ve 3:45 UTC (mimo hourly-jobs v :05)
select cron.schedule('compact-night-raw', '45 3 * * *', $$select private.compact_old_night_raw()$$);
