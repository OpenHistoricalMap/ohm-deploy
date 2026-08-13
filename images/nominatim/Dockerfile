FROM mediagis/nominatim:5.3.2

ENV OPENHISTORICALMAP_NOMINATIM_GITSHA=0106a3174db172ff3f7ceff0d5568e791ca7e0cf
ENV OHM_NOMINATIM_URL=https://codeload.github.com/OpenHistoricalMap/Nominatim/tar.gz/${OPENHISTORICALMAP_NOMINATIM_GITSHA}
ENV COUNTRY_GRID_URL=https://www.nominatim.org/data/country_grid.sql.gz
# use DateFunctions-plpgsql for Nominatim  as we do in imposm
ENV DATEFUNCTIONS_GITSHA=90d8d0f0daea4c8c5aa62edf440f26e9eb0ab950
ENV DATEFUNCTIONS_URL=https://raw.githubusercontent.com/OpenHistoricalMap/DateFunctions-plpgsql/${DATEFUNCTIONS_GITSHA}/datefunctions.sql

RUN apt-get update && \
    apt-get -y install --no-install-recommends \
        cron \
        wget lua5.3 liblua5.3-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Replace the released nominatim-db/nominatim-api with the OHM fork.
RUN set -eux; \
    curl -fsSL "${OHM_NOMINATIM_URL}" -o /tmp/nominatim.tar.gz; \
    mkdir -p /tmp/nominatim-src; \
    tar -xzf /tmp/nominatim.tar.gz -C /tmp/nominatim-src --strip-components=1; \
    curl -fsSL -A "OpenHistoricalMap/ohm-deploy" "${COUNTRY_GRID_URL}" -o /tmp/nominatim-src/data/country_osm_grid.sql.gz; \
    pip install --break-system-packages --force-reinstall --no-deps \
        /tmp/nominatim-src/packaging/nominatim-db \
        /tmp/nominatim-src/packaging/nominatim-api; \
    rm -rf /tmp/nominatim.tar.gz /tmp/nominatim-src

# OHM date functions, added to the SQL that Nominatim loads with `refresh --functions`.
# start.sh runs that on every boot, so the functions are created before the API starts.
RUN set -eux; \
    SQLDIR=$(python3 -c "import nominatim_db, pathlib; print(pathlib.Path(nominatim_db.__file__).parent / 'resources' / 'lib-sql')"); \
    curl -fsSL "${DATEFUNCTIONS_URL}" -o "${SQLDIR}/functions/ohm-datefunctions.sql"; \
    echo "{% include('functions/ohm-datefunctions.sql') %}" >> "${SQLDIR}/functions.sql"

COPY docker-entrypoint.sh /app/
COPY update.sh /app/

# OHM customizations files
COPY ohm-import.lua /app/ohm-import.lua
COPY address-levels.json /app/address-levels.json

ENV IMPORT_STYLE=/app/ohm-import.lua

# Ensure scripts are executable
RUN chmod +x /app/docker-entrypoint.sh /app/update.sh

# start.sh runs replication with a single indexing thread by default.
# Inject --threads so it uses the THREADS env var (falls back to 4).
RUN sed -i 's|nominatim replication --project-dir ${PROJECT_DIR}|& --threads ${THREADS:-4}|' /app/start.sh

RUN echo "* * * * * bash /app/update.sh >> /var/log/cron.log 2>&1" | crontab -

CMD ["/app/docker-entrypoint.sh"]
