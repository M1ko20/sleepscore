#!/bin/bash
# Lokální test SQL logiky: dočasný cluster Postgres 16 + stub Supabase + všechny migrace + testy.
# Použití: supabase/tests/local/run.sh [test.sql …]   (bez argumentu všechny *_test.sql v supabase/tests/local a supabase/tests)
set -euo pipefail
export LC_ALL=C
PG=/opt/homebrew/opt/postgresql@16/bin
HERE="$(cd "$(dirname "$0")" && pwd)"
MIG="$HERE/../../migrations"
TMP="$(mktemp -d)"
PORT=${PGTEST_PORT:-55432}
trap '$PG/pg_ctl -D "$TMP/data" stop -m fast >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

$PG/initdb -D "$TMP/data" -U postgres --auth=trust >/dev/null
$PG/pg_ctl -D "$TMP/data" -o "-p $PORT -k $TMP -c listen_addresses=''" -l "$TMP/log" start >/dev/null
PSQLC="$PG/psql -h $TMP -p $PORT -U postgres -v ON_ERROR_STOP=1 -q"
$PSQLC -d postgres -c "create database tmpl"
PSQL="$PSQLC -d tmpl"

$PSQL -f "$HERE/stub.sql"
for f in "$MIG"/*.sql; do
  # pg_cron lokálně není → nahrazuje ho stub ve schématu cron
  if ! sed 's/^create extension if not exists pg_cron;//' "$f" | $PSQL >/dev/null 2>"$TMP/err"; then
    echo "MIGRACE SELHALA: $f"; cat "$TMP/err"; exit 1
  fi
done
echo "migrace OK ($(ls "$MIG"/*.sql | wc -l | tr -d ' '))"

tests=("$@")
[ ${#tests[@]} -eq 0 ] && tests=("$HERE"/*_test.sql "$HERE"/../*_test.sql)
for t in "${tests[@]}"; do
  echo "== $(basename "$t")"
  # každý test dostane čistou kopii DB po migracích
  $PSQLC -d postgres -c "drop database if exists t" -c "create database t template tmpl"
  $PSQLC -d t -o /dev/null -f "$t" 2>&1 | sed 's/^psql:[^ ]* //'
done
