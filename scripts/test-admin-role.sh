#!/bin/sh
set -eu
admin_pg_bin="${ADMIN_PG_BIN:-/Library/PostgreSQL/18/bin}"
admin_pg_dir=$(mktemp -d /tmp/humour-role-pg.XXXXXX)
"$admin_pg_bin/initdb" -D "$admin_pg_dir/data" -A trust --no-locale > "$admin_pg_dir/init.log"
trap '"$admin_pg_bin/pg_ctl" -D "$admin_pg_dir/data" -m fast -w stop > "$admin_pg_dir/stop.log" 2>&1 || true' EXIT
"$admin_pg_bin/pg_ctl" -D "$admin_pg_dir/data" -l "$admin_pg_dir/server.log" -o "-h '' -k $admin_pg_dir -p 55501" -w start
"$admin_pg_bin/psql" -h "$admin_pg_dir" -p 55501 -d postgres -v ON_ERROR_STOP=1 -f scripts/test-admin-role.sql
printf '%s\n' 'Passed role checks: admin-only grants/revokes, last-admin protection, stale-state rejection, Google identity, and protected audit log.'
