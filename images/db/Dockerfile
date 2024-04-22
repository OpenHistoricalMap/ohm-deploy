FROM postgres:14
RUN apt-get update \
    && apt-get install -y \
    postgresql-server-dev-14 \
    make \
    build-essential \
    postgresql-14-postgis-3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ADD functions/functions.sql /usr/local/share/osm-db-functions.sql
ADD docker_postgres.sh /docker-entrypoint-initdb.d/
RUN mkdir -p db
RUN mkdir -p lib
ADD functions/ db/functions/
ADD lib/quad_tile/ lib/quad_tile/
RUN make -C db/functions/
RUN chown -R postgres lib/
RUN chown -R postgres db/

## Validate postgresql.conf file 
COPY config/postgresql.conf /etc/postgresql/postgresql.conf
RUN mkdir /var/lib/postgresql/test_data
RUN chown postgres:postgres /var/lib/postgresql/test_data
USER postgres
RUN initdb -D /var/lib/postgresql/test_data
USER root

# Set the default command to run PostgreSQL
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]