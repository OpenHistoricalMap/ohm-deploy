FROM postgis/postgis:12-3.1
RUN apt-get update
RUN apt-get install -y git ca-certificates

COPY ./config/docker-entrypoint.sh /usr/local/bin/
RUN mkdir -p /docker-entrypoint-initdb.d
COPY ./config/update_db.sh /docker-entrypoint-initdb.d
COPY ./config/update_postgresql.sh /docker-entrypoint-initdb.d

RUN git clone https://github.com/OpenHistoricalMap/DateFunctions-plpgsql.git /usr/local/datefunctions
WORKDIR /usr/local/datefunctions
# deploy improvements to negative year handling
RUN git checkout d9f06a4ac0674881247c38b29ba58ff1d167b7bb
RUN cp datefunctions.sql /docker-entrypoint-initdb.d/datefunctions.sql
