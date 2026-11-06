-- Plánované úlohy přes pg_cron (běží v databázi, Free tier OK).
create extension if not exists pg_cron;

-- každou hodinu v :05 – uzavírání výzev, díry v sériích, Dvojí život
select cron.schedule('hourly-jobs', '5 * * * *', $$select private.hourly_jobs()$$);

-- úklid historie běhů pg_cron (jinak tabulka roste)
select cron.schedule('cron-history-cleanup', '30 3 * * *',
  $$delete from cron.job_run_details where end_time < now() - interval '7 days'$$);
