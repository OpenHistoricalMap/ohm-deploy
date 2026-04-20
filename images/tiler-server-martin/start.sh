#!/usr/bin/env bash
set -euo pipefail

echo "=== Martin Tile Server Setup ==="

export MARTIN_INTERNAL_PORT="${MARTIN_INTERNAL_PORT:-3001}"
export MARTIN_NGINX_PORT="${MARTIN_NGINX_PORT:-80}"
export MARTIN_NGINX_GZIP="${MARTIN_NGINX_GZIP:-on}"                    # on | off
export MARTIN_NGINX_GZIP_COMP_LEVEL="${MARTIN_NGINX_GZIP_COMP_LEVEL:-4}" # 1-9

# Wait for PostgreSQL
echo "Waiting for PostgreSQL to be ready..."
until pg_isready -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -p "${POSTGRES_PORT}" > /dev/null 2>&1; do
  sleep 1
done
echo "PostgreSQL is ready."

# Export languages bbox feed to GeoJSON and upload to S3
echo "Extracting languages to geojson..."
python3 /app/scripts/lang2geojson.py

# Generate and create function sources in PostgreSQL
echo "Generating function sources..."
python3 /app/scripts/generate_functions.py

# Generate config.yaml from environment variables
echo "Generating Martin config..."
cat > /app/config/config.yaml <<EOF
listen_addresses: '0.0.0.0:${MARTIN_INTERNAL_PORT}'
worker_processes: ${MARTIN_WORKER_PROCESSES:-8}
# Disable Martin's internal tile cache so tiles are always generated fresh.
# Nginx handles caching with TTLs + ?fresh_tiles=1 bypass.
cache_size_mb: 0

postgres:
  connection_string: 'postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}?connect_timeout=10&keepalives=1&keepalives_idle=30'
  pool_size: ${MARTIN_POOL_SIZE:-50}
  default_srid: 3857
  auto_publish:
    tables: false
    functions:
      from_schemas: public
EOF
echo "Martin config written."

# Generate nginx.conf with composite routes from functions.json
echo "Generating nginx config..."
python3 /app/scripts/generate_nginx_conf.py

# Ensure nginx dirs exist
mkdir -p /run/nginx /var/log/nginx /var/cache/nginx/tiles /app/tilejson

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
echo "Starting Nginx on port ${MARTIN_NGINX_PORT}..."
nginx -c /app/config/nginx.conf -g 'daemon off;' &
NGINX_PID=$!

echo "=== Ready ==="
echo "  Nginx  :${MARTIN_NGINX_PORT} -> Martin :${MARTIN_INTERNAL_PORT}"
echo "  Composite: /maps/ohm/{z}/{x}/{y}.pbf (all layers)"
echo "  Per-layer: /maps/ohm/land_ohm_lines/{z}/{x}/{y}.pbf"

# Wait for either process to exit
wait -n $MARTIN_PID $NGINX_PID
exit $?
