#!/usr/bin/env bash
# Backend tests for HarvestLink on Oracle Database 23ai Free in Docker.
#
# Installs db/ into a throwaway user, runs every db/tests/test_*.sql, checks
# that uninstall.sql removes everything, then drops the user. Exits non-zero
# if any assertion or SQL statement fails.
#
#   db/tests/run.sh                          # start (or reuse) hl-test-oracle
#   HL_TEST_CONTAINER=harvestlink-oracle db/tests/run.sh   # reuse another container
#
# Needs only Docker. The container runs gvenzl/oracle-free:23-slim-faststart.
set -euo pipefail

CONTAINER="${HL_TEST_CONTAINER:-hl-test-oracle}"
IMAGE="gvenzl/oracle-free:23-slim-faststart"
DB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_USER="hltest_$(date +%s)"
TEST_PW="T$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')x"
WORK="/tmp/${TEST_USER}"

log() { printf '\n== %s\n' "$*"; }

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    docker start "$CONTAINER" >/dev/null
  else
    log "Starting $CONTAINER ($IMAGE)"
    docker run -d --name "$CONTAINER" \
      -e ORACLE_PASSWORD="$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
      "$IMAGE" >/dev/null
  fi
  log "Waiting for the database"
  # Read the logs into a variable: piping them into grep -q under pipefail can
  # report failure (SIGPIPE) even when the line is there
  ready=""
  for _ in $(seq 1 150); do
    logs="$(docker logs "$CONTAINER" 2>&1 || true)"
    if [[ "$logs" == *"DATABASE IS READY TO USE"* ]]; then ready=1; break; fi
    sleep 2
  done
  [[ -n "$ready" ]] || { echo "Database did not start"; docker logs --tail 30 "$CONTAINER" 2>&1; exit 1; }
fi

docker cp "$DB_DIR" "$CONTAINER:$WORK" >/dev/null

sysdba() { docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 -w "$WORK" "$CONTAINER" sqlplus -s -L / as sysdba; }

cleanup() {
  sysdba >/dev/null 2>&1 <<SQL || true
alter session set container=FREEPDB1;
drop user ${TEST_USER} cascade;
SQL
  docker exec "$CONTAINER" rm -rf "$WORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

log "Installing into ${TEST_USER}"
TESTS=$(cd "$DB_DIR/tests" && ls test_*.sql | sort)
{
  cat <<SQL
whenever sqlerror exit failure rollback
set define off feedback off serveroutput on size unlimited lines 200 pages 0 trimspool on
alter session set container=FREEPDB1;
create user ${TEST_USER} identified by "${TEST_PW}" quota unlimited on users;
grant create session, create table, create view, create sequence, create procedure, create trigger to ${TEST_USER};
grant execute on sys.dbms_crypto to ${TEST_USER};
connect ${TEST_USER}/"${TEST_PW}"@localhost/FREEPDB1
set define off feedback off serveroutput on size unlimited
@install.sql
prompt INSTALL OK
@tests/assert.sql
SQL
  for t in $TESTS; do
    printf 'prompt\nprompt -- %s\n@tests/%s\n' "$t" "$t"
  done
  cat <<SQL
exec hlt.summary
@uninstall.sql
declare n number; begin
  select count(*) into n from user_objects where object_name <> 'HLT';
  if n > 0 then raise_application_error(-20999, 'uninstall.sql left ' || n || ' objects'); end if;
end;
/
prompt UNINSTALL OK
exit success
SQL
} | sysdba | tee "/tmp/${TEST_USER}.log" | grep -E '^(PASS|FAIL|INSTALL OK|UNINSTALL OK|-- |ORA-|SP2-|RESULT)' || true

if grep -q '^UNINSTALL OK' "/tmp/${TEST_USER}.log" && ! grep -q '^FAIL' "/tmp/${TEST_USER}.log"; then
  log "All backend tests passed"
  rm -f "/tmp/${TEST_USER}.log"
  exit 0
fi
log "Backend tests FAILED (full log: /tmp/${TEST_USER}.log)"
exit 1
