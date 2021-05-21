FROM postgis/postgis:12-3.1
RUN apt-get update
RUN apt-get install -y git ca-certificates

COPY ./config/docker-entrypoint.sh /usr/local/bin/
RUN mkdir -p /docker-entrypoint-initdb.d
COPY ./config/update_db.sh /docker-entrypoint-initdb.d
COPY ./config/update_postgresql.sh /docker-entrypoint-initdb.d

RUN git clone https://github.com/Open-Historical-Map-Labs/DateFunctions-plpgsql.git /usr/local/datefunctions
WORKDIR /usr/local/datefunctions
# deploy invalid datetime parsing fix
RUN git checkout 02618f4a8c7ef75bab53fb9b1c75e7aff3d98a2c
RUN cp datefunctions.sql /docker-entrypoint-initdb.d/datefunctions.sql
