#!/usr/bin/env bash
# Runs the database tests on a throwaway local Postgres database.
# Needs PostgreSQL installed locally. Usage: supabase/tests/run_tests.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
DB=swimbase_test
PSQL="psql -v ON_ERROR_STOP=1 -q -X"
dropdb --if-exists "$DB" >/dev/null
createdb "$DB"
$PSQL -d "$DB" -f supabase/tests/supabase_stub.sql
for f in supabase/migrations/*.sql; do
  $PSQL -d "$DB" -f "$f"
done
$PSQL -d "$DB" -o /dev/null -f supabase/tests/privacy_rules_test.sql
$PSQL -d "$DB" -o /dev/null -f supabase/tests/schedule_test.sql
dropdb "$DB"
