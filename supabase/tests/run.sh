#!/usr/bin/env bash
# Applies the migrations to a throwaway Postgres in Docker and runs the backend rule tests.
# This checks the SQL logic (constraints, triggers, functions, row-level security). It uses a
# small shim instead of real Supabase auth/storage, so it is not a substitute for testing
# against an actual Supabase project.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=deconstructed-sql-test
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -e POSTGRES_PASSWORD=postgres postgres:17-alpine >/dev/null
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 60); do
  if docker exec "$NAME" psql -U postgres -c 'select 1' >/dev/null 2>&1; then break; fi
  sleep 1
done
sleep 1

run() { docker exec -i "$NAME" psql -U postgres -v ON_ERROR_STOP=1 -q "$@"; }

run < tests/00_supabase_shim.sql
for migration in migrations/*.sql; do
  echo "applying $migration"
  run < "$migration"
done
run < tests/rules_test.sql
