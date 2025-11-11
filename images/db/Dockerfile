FROM developmentseed/osmseed-replication-job:0.1.0-0.dev.git.975.h2bc8003 AS replication-job
FROM postgres:17
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-server-dev-17 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=replication-job /osmdbt/postgresql-plugin/build/osm-logical.so /usr/lib/postgresql/17/lib/osm-logical.so
RUN chown postgres:postgres /usr/lib/postgresql/17/lib/osm-logical.so && \
    chmod 755 /usr/lib/postgresql/17/lib/osm-logical.so
