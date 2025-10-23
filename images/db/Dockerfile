FROM postgres:17

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql-17-postgis-3 \
        postgresql-17-postgis-3-scripts \
        postgis \
    && rm -rf /var/lib/apt/lists/*

COPY openstreetmap-postgres-init.sh /docker-entrypoint-initdb.d/