#!/usr/bin/env bash
# Usage: HOSTGROUP=<writer_hostgroup> ensure-proxysql-user.sh <db_user>
# Registers one site's DB user in the correct ProxySQL writer hostgroup.
set -Eeuo pipefail

TARGET="${1:?Usage: HOSTGROUP=<writer_hostgroup> $0 <db_user>}"

GALERA_HOST="${GALERA_HOST:?GALERA_HOST is not set}"
GALERA_PORT="${GALERA_PORT:-3306}"
SYNC_USER="${SYNC_USER:?SYNC_USER is not set}"
SYNC_PW="${SYNC_PW:?SYNC_PW is not set}"
PX_HOST="${PX_HOST:?PX_HOST is not set}"
PX_ADMIN_PORT="${PX_ADMIN_PORT:-6032}"
PX_ADMIN_USER="${PX_ADMIN_USER:-radmin}"
PX_ADMIN_PW="${PX_ADMIN_PW:?PX_ADMIN_PW is not set}"
HOSTGROUP="${HOSTGROUP:?HOSTGROUP must be explicitly set}"
RETRIES="${RETRIES:-10}"
RETRY_SLEEP="${RETRY_SLEEP:-1}"
LOCK_FILE="${LOCK_FILE:-/tmp/proxysql-user-sync.lock}"

[[ "$TARGET" != "--all" ]] || {
  echo "[user-sync] --all is disabled for shard-aware registration" >&2
  exit 64
}
[[ "$TARGET" =~ ^[A-Za-z0-9_]{1,64}$ ]] || {
  echo "[user-sync] invalid database username" >&2
  exit 64
}
[[ "$HOSTGROUP" =~ ^[1-9][0-9]*$ ]] || {
  echo "[user-sync] HOSTGROUP must be a positive integer" >&2
  exit 64
}

MYSQL_BIN="$(command -v mariadb || command -v mysql || true)"
[[ -n "$MYSQL_BIN" ]] || {
  echo "[user-sync] no mariadb/mysql client in image" >&2
  exit 127
}

log() {
  echo "$(date -u +%FT%TZ) [user-sync] $*" >&2
}

galera() {
  MYSQL_PWD="$SYNC_PW" "$MYSQL_BIN" \
    -h"$GALERA_HOST" -P"$GALERA_PORT" -u"$SYNC_USER" \
    -N -B --connect-timeout=5 "$@"
}

admin() {
  MYSQL_PWD="$PX_ADMIN_PW" "$MYSQL_BIN" \
    -h"$PX_HOST" -P"$PX_ADMIN_PORT" -u"$PX_ADMIN_USER" \
    -N -B --connect-timeout=5 "$@"
}

exec 9>"$LOCK_FILE"
flock -w 60 9 || {
  log "could not get lock"
  exit 75
}

fetch_desired() {
  galera -e "SET SESSION wsrep_sync_wait=1;
             SELECT DISTINCT User, Password
             FROM mysql.user
             WHERE User='$TARGET' AND Password <> '';" |
    LC_ALL=C sort
}

fetch_current() {
  admin -e "SELECT DISTINCT username, password, default_hostgroup
            FROM runtime_mysql_users
            WHERE username='$TARGET';" |
    LC_ALL=C sort
}

desired=""
for ((i=1; i<=RETRIES; i++)); do
  if desired="$(fetch_desired 2>/dev/null)" && [[ -n "$desired" ]]; then
    break
  fi
  desired=""
  sleep "$RETRY_SLEEP"
done

if [[ -z "$desired" ]]; then
  log "user '$TARGET' not found on Galera after $RETRIES attempts"
  exit 2
fi

sql=""
expected=""

while IFS=$'\t' read -r u h; do
  if [[ "$u" =~ ^[A-Za-z0-9_]{1,64}$ &&
        "$h" =~ ^\*[0-9A-Fa-f]{40}$ ]]; then
    sql+="REPLACE INTO mysql_users(username,password,default_hostgroup,active) VALUES ('$u','$h',$HOSTGROUP,1);"
    expected+="${u}"$'\t'"${h}"$'\t'"${HOSTGROUP}"$'\n'
  else
    log "unexpected user/password format returned for '$TARGET'"
    exit 6
  fi
done <<< "$desired"

[[ -n "$sql" ]] || {
  log "no valid user record found for '$TARGET'"
  exit 6
}

expected="$(printf '%s' "$expected" | LC_ALL=C sort)"
current="$(fetch_current)" || {
  log "cannot read ProxySQL admin at $PX_HOST:$PX_ADMIN_PORT"
  exit 3
}

if [[ "$current" == "$expected" ]]; then
  log "user '$TARGET' is already in writer hostgroup $HOSTGROUP"
  exit 0
fi

admin -e "${sql}LOAD MYSQL USERS TO RUNTIME; SAVE MYSQL USERS TO DISK;" || {
  log "failed applying user to ProxySQL"
  exit 4
}

current="$(fetch_current)" || {
  log "cannot verify ProxySQL runtime users"
  exit 5
}

[[ "$current" == "$expected" ]] || {
  log "runtime mismatch: expected user '$TARGET' in hostgroup $HOSTGROUP"
  log "actual ProxySQL row: $current"
  exit 5
}

log "successfully synced user '$TARGET' to writer hostgroup $HOSTGROUP"
