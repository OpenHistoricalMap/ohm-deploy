FROM postgis/postgis:17-3.5

RUN apt-get update 
RUN apt-get install -y --no-install-recommends \
    wget gnupg2 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    echo "deb http://apt.postgresql.org/pub/repos/apt $(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list

# Install PostgreSQL and `pg_cron`
RUN apt-get update && \
    apt-get install -y --no-install-recommends git ca-certificates \
    postgresql-17-cron && \
    rm -rf /var/lib/apt/lists/*

COPY ./scripts/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
RUN mkdir -p /docker-entrypoint-initdb.d

COPY ./scripts/update_db.sh /docker-entrypoint-initdb.d/
COPY ./scripts/update_postgresql.sh /docker-entrypoint-initdb.d/
WORKDIR /usr/local/datefunctions
RUN git clone https://github.com/OpenHistoricalMap/DateFunctions-plpgsql.git .

# Deploy improvements to negative year handling
RUN git checkout d9f06a4ac0674881247c38b29ba58ff1d167b7bb
RUN cp datefunctions.sql /docker-entrypoint-initdb.d/datefunctions.sql
