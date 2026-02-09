#!/usr/bin/env bash
set -euo pipefail

echo "=== Martin Tile Server Setup ==="

MARTIN_INTERNAL_PORT="${MARTIN_INTERNAL_PORT:-3001}"
NGINX_PORT="${NGINX_PORT:-80}"

# Wait for PostgreSQL
echo "Waiting for PostgreSQL to be ready..."
until pg_isready -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -p "${POSTGRES_PORT}" > /dev/null 2>&1; do
  sleep 1
done
echo "PostgreSQL is ready."

# Create the function source in PostgreSQL
echo "Creating function sources..."
for sql_file in /app/sql_functions/*.sql; do
  echo "  Executing: $(basename "$sql_file")"
  PGPASSWORD="${POSTGRES_PASSWORD}" psql -v ON_ERROR_STOP=1 -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    -f "$sql_file"
done
echo "Function sources created."

# Generate config.yaml from environment variables
echo "Generating Martin config..."
cat > /app/config/config.yaml <<EOF
listen_addresses: '0.0.0.0:${MARTIN_INTERNAL_PORT}'
worker_processes: ${MARTIN_WORKER_PROCESSES:-8}

postgres:
  connection_string: 'postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}'
  pool_size: ${MARTIN_POOL_SIZE:-20}
  default_srid: 3857
  auto_publish:
    tables: false
    functions:
      from_schemas: public
EOF
echo "Martin config written."

# Ensure nginx dirs exist
mkdir -p /run/nginx /var/log/nginx

# Start Martin in background
echo "Starting Martin on port ${MARTIN_INTERNAL_PORT}..."
martin --config /app/config/config.yaml &
MARTIN_PID=$!

# Wait for Martin to be ready
until curl -sf "http://127.0.0.1:${MARTIN_INTERNAL_PORT}/health" > /dev/null 2>&1; do
  sleep 1
done
echo "Martin is ready."

# Start Nginx in foreground
echo "Starting Nginx on port ${NGINX_PORT}..."
nginx -c /app/config/nginx.conf -g 'daemon off;' &
NGINX_PID=$!

echo "=== Ready ==="
echo "  Nginx  :${NGINX_PORT} -> Martin :${MARTIN_INTERNAL_PORT}"
echo "  Layer:  /land_ohm_lines/{z}/{x}/{y}"
echo "  Tegola: /maps/osm/land_ohm_lines/{z}/{x}/{y}.pbf"

# Wait for either process to exit
wait -n $MARTIN_PID $NGINX_PID
exit $?
