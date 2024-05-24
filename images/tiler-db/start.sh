#!/bin/bash
ENVIRONMENT=${ENVIRONMENT:-production}
CONFIG_FILE=/etc/postgresql/postgresql.${ENVIRONMENT}.conf
LOG_STATEMENT=${LOG_STATEMENT:-none}
echo "Starting PostgreSQL using ${CONFIG_FILE}"
exec su postgres -c "postgres -c config_file=${CONFIG_FILE} -c log_statement=${LOG_STATEMENT}"
