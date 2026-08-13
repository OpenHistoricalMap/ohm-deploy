#!/bin/bash -e
CONFIG_FILE=${PROJECT_DIR}/.env

# Address levels config is baked into the image
echo NOMINATIM_ADDRESS_LEVEL_CONFIG=/app/address-levels.json >> ${CONFIG_FILE}

# Nominatim reads node 1 from the OSM API to date the database, so point it at OHM
if [[ ! -z "$OSMSEED_WEB_API_DOMAIN" ]]; then
    SITE_PACKAGES=$(python3 -c "import nominatim_db, pathlib; print(pathlib.Path(nominatim_db.__file__).parent.parent)")
    find "${SITE_PACKAGES}/nominatim_db" "${SITE_PACKAGES}/nominatim_api" -name '*.py' -print0 |
        xargs -0 perl -pi -e "s/www\.openstreetmap\.org/${OSMSEED_WEB_API_DOMAIN}/g"
fi

# Cron runs with a minimal environment, so save THREADS for update.sh
echo "export THREADS=${THREADS:-4}" > /app/cron-env.sh

# Cron job is going activate updates even if the script fails once, next time it will start again
cron & /app/start.sh
