#!/bin/sh
set -e

# Add hstore and pg_cron into the DB
for DB in template_postgis "$POSTGRES_DB" "${@}"; do
    echo "Updating extensions '$DB'"
    psql --dbname="$DB" -c "
        CREATE EXTENSION IF NOT EXISTS hstore;
        CREATE EXTENSION IF NOT EXISTS pg_cron;
    "
done
