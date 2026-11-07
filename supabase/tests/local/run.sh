#!/bin/zsh
# Lokální test SQL: čistá DB „sleep_test“ se stuby Supabase + všechny migrace + zadaný test.
# Předpoklad: běžící Postgres 16 (PGHOST/PGPORT/PGUSER, default 127.0.0.1:5432, postgres).
#   supabase/tests/local/run.sh supabase/tests/notifications_test.sql
set -e
export LC_ALL=C
export PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH
export PGHOST=${PGHOST:-127.0.0.1} PGPORT=${PGPORT:-5432} PGUSER=${PGUSER:-postgres}
HERE=${0:A:h}
ROOT=${HERE:h:h:h}
DB=sleep_test

psql -qc "drop database if exists $DB" >/dev/null 2>&1
psql -qc "create database $DB" >/dev/null
psql -qc "do \$\$ begin create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls; exception when duplicate_object then null; end \$\$" >/dev/null
psql -d $DB -q -v ON_ERROR_STOP=1 -f $HERE/stub.sql >/dev/null
for f in $ROOT/supabase/migrations/*.sql; do
  # pg_cron lokálně není → stub ve stub.sql
  grep -v "create extension if not exists pg_cron" $f | psql -d $DB -q -v ON_ERROR_STOP=1 >/dev/null \
    || { echo "migrace selhala: $f"; exit 1; }
done
for t in "$@"; do
  psql -d $DB -q -v ON_ERROR_STOP=1 -f $t
done
