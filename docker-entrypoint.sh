#!/bin/bash
set -euo pipefail

PGDATA="${PGDATA:-/var/lib/pgsql/16/data}"
PG_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
PGROLE="${PGROLE:-primary}"
PG_REPLICATION_USER="${PG_REPLICATION_USER:-replicator}"
PG_REPLICATION_PASSWORD="${PG_REPLICATION_PASSWORD:-replicator}"
PG_STANDBY_NAME="${PG_STANDBY_NAME:-standby1}"
PRIMARY_HOST="${PRIMARY_HOST:-pg-primary}"
PRIMARY_PORT="${PRIMARY_PORT:-5432}"

# HELPERS

write_pgpass() {
    local host="$1" port="$2" user="$3" password="$4"
    echo "${host}:${port}:replication:${user}:${password}" > ~/.pgpass
    chmod 600 ~/.pgpass
}

remove_pgpass() {
    rm -f ~/.pgpass
}

# PRIMARY
init_primary() {
    if [ ! -s "$PGDATA/PG_VERSION" ]; then
        echo "[primary] Initializing database..."

        echo "$PG_PASSWORD" > /tmp/pwfile
        initdb -D "$PGDATA" \
            -k \
            --auth=scram-sha-256 \
            --auth-host=scram-sha-256 \
            --auth-local=scram-sha-256 \
            --pwfile=/tmp/pwfile
        rm /tmp/pwfile

        # Accept connections from anywhere
        echo "listen_addresses = '*'" >> "$PGDATA/postgresql.conf"

        # Replication settings
        cat >> "$PGDATA/postgresql.conf" <<EOF

# Replication
wal_level = replica
max_wal_senders = 10
wal_keep_size = 1024
synchronous_commit = on
synchronous_standby_names = '${PG_STANDBY_NAME}'
EOF

        # pg_hba: app connections + replication connections for standby
        cat >> "$PGDATA/pg_hba.conf" <<EOF
host    all             all                     0.0.0.0/0   scram-sha-256
host    replication     ${PG_REPLICATION_USER}  0.0.0.0/0   scram-sha-256
EOF

        # Start temporarily (Unix socket only, trust auth, no sync replication)
        echo "local all all trust" > /tmp/pg_hba_init.conf
        pg_ctl start -D "$PGDATA" \
            -o "-c listen_addresses='' -c hba_file=/tmp/pg_hba_init.conf -c synchronous_standby_names=''" \
            -w

        psql -v ON_ERROR_STOP=1 -U postgres \
            -c "CREATE USER ${PG_REPLICATION_USER} WITH REPLICATION ENCRYPTED PASSWORD '${PG_REPLICATION_PASSWORD}';"

        pg_ctl stop -D "$PGDATA" -m fast -w
        rm /tmp/pg_hba_init.conf
        echo "[primary] Initialization complete"
    else
        echo "[primary] Using existing data directory"
    fi
}

# STANDBY
init_standby() {
    if [ ! -s "$PGDATA/PG_VERSION" ]; then
        echo "[standby] Waiting for primary at ${PRIMARY_HOST}:${PRIMARY_PORT}..."

        until pg_isready -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U postgres; do
            echo "[standby] Primary not ready, retrying in 2s..."
            sleep 2
        done

        echo "[standby] Running pg_basebackup from primary..."

        write_pgpass "$PRIMARY_HOST" "$PRIMARY_PORT" "$PG_REPLICATION_USER" "$PG_REPLICATION_PASSWORD"

        pg_basebackup \
            -h "$PRIMARY_HOST" \
            -p "$PRIMARY_PORT" \
            -U "$PG_REPLICATION_USER" \
            -D "$PGDATA" \
            -P \
            -Xs \
            -R

        remove_pgpass

        # Overwrite postgresql.auto.conf written by -R with full primary_conninfo
        # including password and application_name. auto.conf takes precedence over
        # postgresql.conf so this is the correct file to write.
        cat > "$PGDATA/postgresql.auto.conf" <<EOF
# Written by docker-entrypoint.sh
primary_conninfo = 'host=${PRIMARY_HOST} port=${PRIMARY_PORT} user=${PG_REPLICATION_USER} password=${PG_REPLICATION_PASSWORD} application_name=${PG_STANDBY_NAME}'
EOF

        echo "[standby] Base backup complete, starting in standby mode"
    else
        echo "[standby] Using existing data directory"
    fi
}

check_standby_health() {
    local status
    status=$(PGPASSWORD="${PG_PASSWORD}" psql -U postgres -tAc "SELECT status FROM pg_stat_wal_receiver;" 2>/dev/null)
    if [ "$status" = "streaming" ]; then
        exit 0
    else
        echo "[standby] Replication status: '${status:-unknown}'"
        exit 1
    fi
}

# MAIN
if [ "${1:-}" = "healthcheck" ]; then
    case "$PGROLE" in
        primary) pg_isready -U postgres ;;
        standby) check_standby_health ;;
    esac
    exit $?
fi

case "$PGROLE" in
    primary)
        init_primary
        ;;
    standby)
        init_standby
        ;;
    *)
        echo "ERROR: PGROLE must be 'primary' or 'standby', got '${PGROLE}'"
        exit 1
        ;;
esac

exec postgres -D "$PGDATA"

