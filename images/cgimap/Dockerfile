FROM ruby:3.3.0 AS builder
ENV DEBIAN_FRONTEND=noninteractive
ENV workdir=/var/www
ENV CGIMAP_GITSHA=8ea707e10aeab5698e6859856111816d75354592
RUN apt-get update && apt-get install -y \
    build-essential cmake git-core curl file \
    libxml2-dev libpqxx-dev libfcgi-dev zlib1g-dev libbrotli-dev \
    libboost-program-options-dev libfmt-dev libmemcached-dev libcrypto++-dev \
    libargon2-dev libyajl-dev libapache2-mod-fcgid \
    && rm -rf /var/lib/apt/lists/*
ENV cgimap=/tmp/openstreetmap-cgimap
RUN git clone -b master https://github.com/zerebubuth/openstreetmap-cgimap.git $cgimap \
    && cd $cgimap \
    && git checkout $CGIMAP_GITSHA \
    && sed -i 's#OpenStreetMap and contributors#OpenHistoricalMap is dedicated to the public domain except where otherwise noted.#g' include/cgimap/output_formatter.hpp \
    && sed -i 's#http://www.openstreetmap.org/copyright#https://www.openhistoricalmap.org/copyright#g' include/cgimap/output_formatter.hpp \
    && sed -i 's#http://opendatacommons.org/licenses/odbl/1-0/#https://creativecommons.org/public-domain/cc0/#g' include/cgimap/output_formatter.hpp \
    && mkdir build && cd build && cmake .. && cmake --build .

FROM ruby:3.3.0
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    libxml2 libpqxx-6.4 libfcgi zlib1g libbrotli1 \
    libboost-program-options1.74.0 libfmt-dev libmemcached11 libcrypto++8 \
    libargon2-1 libyajl2 libapache2-mod-fcgid postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    apt-get update && \
    apt-get install -y postgresql-client

COPY --from=builder /tmp/openstreetmap-cgimap/build/openstreetmap-cgimap /usr/local/bin/openstreetmap-cgimap
RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/local_libs.conf && ldconfig
COPY *.sh /
CMD [ "/start.sh" ]
