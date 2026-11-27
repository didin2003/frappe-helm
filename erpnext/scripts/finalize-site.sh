#!/usr/bin/env bash
# Usage: HOSTGROUP=<writer_hostgroup> finalize-site.sh <site>
# Register the site's DB user, verify ProxySQL login, then cut over the site.
set -Eeuo pipefail

SITE="${1:?Usage: HOSTGROUP=<writer_hostgroup> $0 <site>}"
HOSTGROUP="${HOSTGROUP:?HOSTGROUP must be set}"
DB_HOST="${DB_HOST:?DB_HOST is not set}"
DB_PORT="${DB_PORT:-6033}"

export PX_HOST="${PX_HOST:-$DB_HOST}"
PX_PORT="${PX_PORT:-$DB_PORT}"

[[ "$HOSTGROUP" =~ ^[1-9][0-9]*$ ]] || {
  echo "[finalize] invalid HOSTGROUP: $HOSTGROUP" >&2
  exit 64
}

cd /home/frappe/frappe-bench

CFG="sites/${SITE}/site_config.json"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  echo "$(date -u +%FT%TZ) [finalize] $*" >&2
}

[[ -f "$CFG" ]] || {
  log "$CFG not found"
  exit 1
}

MYSQL_BIN="$(command -v mariadb || command -v mysql || true)"
[[ -n "$MYSQL_BIN" ]] || {
  log "no mariadb/mysql client in image"
  exit 127
}

DB_USER="$(jq -r '.db_user // .db_name // empty' "$CFG")"
DB_PW="$(jq -r '.db_password // empty' "$CFG")"

[[ -n "$DB_USER" && -n "$DB_PW" ]] || {
  log "database username or password missing in $CFG"
  exit 1
}

log "registering $DB_USER in writer hostgroup $HOSTGROUP"

if ! HOSTGROUP="$HOSTGROUP" bash "$DIR/ensure-proxysql-user.sh" "$DB_USER"; then
  log "could not register $DB_USER in hostgroup $HOSTGROUP; site config unchanged"
  exit 10
fi

ok=0
for _ in $(seq 1 10); do
  if MYSQL_PWD="$DB_PW" "$MYSQL_BIN" \
       -h"$PX_HOST" -P"$PX_PORT" -u"$DB_USER" "$DB_USER" \
       --connect-timeout=5 -e 'SELECT 1' >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 1
done

if [[ "$ok" -ne 1 ]]; then
  log "login via ProxySQL failed for $DB_USER; site config unchanged"
  exit 11
fi

tmp="${CFG}.tmp.$$"
trap 'rm -f "$tmp"' EXIT

jq --arg h "$PX_HOST" --argjson p "$PX_PORT" \
  '.db_host=$h | .db_port=$p' "$CFG" > "$tmp"

chmod --reference="$CFG" "$tmp"
mv "$tmp" "$CFG"
trap - EXIT

log "OK: $SITE routed through ${PX_HOST}:${PX_PORT} using writer hostgroup $HOSTGROUP"
