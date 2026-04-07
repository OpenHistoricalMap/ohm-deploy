#!/bin/bash
# Setup a dedicated 'imposm' PostgreSQL role with optimized session parameters.
# This avoids affecting Tegola/other services that share the same postgres user.
set -e
source "$(dirname "$0")/utils.sh"

log_message "Setting up imposm database role with optimized parameters..."

psql "$PG_CONNECTION" <<EOSQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'imposm') THEN
        CREATE ROLE imposm LOGIN PASSWORD '${IMPOSM_DB_PASSWORD:-$POSTGRES_PASSWORD}';
        RAISE NOTICE 'Created imposm role';
    END IF;
END
\$\$;

-- Grant superuser to imposm so it has full permissions like postgres
ALTER ROLE imposm SUPERUSER;

-- Session-level parameters (only apply to imposm connections, not Tegola)
ALTER ROLE imposm IN DATABASE $POSTGRES_DB SET work_mem = '${IMPOSM_WORK_MEM:-4GB}';
ALTER ROLE imposm IN DATABASE $POSTGRES_DB SET maintenance_work_mem = '${IMPOSM_MAINTENANCE_WORK_MEM:-24GB}';
ALTER ROLE imposm IN DATABASE $POSTGRES_DB SET temp_buffers = '${IMPOSM_TEMP_BUFFERS:-256MB}';
EOSQL

log_message "Imposm role setup complete."
