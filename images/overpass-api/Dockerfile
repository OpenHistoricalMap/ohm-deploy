FROM debian:bookworm-slim AS builder

RUN apt-get update \
    && apt-get install --no-install-recommends --no-install-suggests -y \
        autoconf \
        automake \
        bash \
        bzip2 \
        ca-certificates \
        curl \
        expat \
        g++ \
        libexpat1-dev \
        liblz4-1 \
        liblz4-dev \
        libtool \
        m4 \
        make \
        wget \
        zlib1g \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

ARG OVERPASS_VERSION
ADD http://dev.overpass-api.de/releases/osm-3s_v0.7.62.9.tar.gz /tmp/src.tar.gz

WORKDIR /tmp/src
RUN tar -x -z --strip-components 1 -f /tmp/src.tar.gz

# Use OHM copyright instead of ODbL/openstreetmap.org. See issue #558.
RUN sed -i \
        -e 's|from www\.openstreetmap\.org|from www.openhistoricalmap.org|g' \
        -e 's|made available under ODbL|made available under CC0|g' \
        overpass_api/frontend/basic_formats.cc \
        overpass_api/output_formats/output_json.cc \
        overpass_api/output_formats/output_xml.cc

RUN autoreconf -f -i \
    && CXXFLAGS='-O2' CFLAGS='-O2' ./configure --prefix=/app --enable-lz4 \
    && make -j "$(nproc)" \
    && make install \
    && cp -r /tmp/src/rules /app/etc/rules

ARG WIKTORN_TAG
FROM wiktorn/overpass-api:v0.7.62.9

COPY --from=builder /app/bin/   /app/bin/
COPY --from=builder /app/etc/   /app/etc/

RUN apt-get update \
    && apt-get install --no-install-recommends --no-install-suggests -y \
        less \
        procps \
    && rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh fix-permissions.sh /app/
RUN chmod +x /app/docker-entrypoint.sh /app/fix-permissions.sh

EXPOSE 80

ENTRYPOINT ["/app/docker-entrypoint.sh"]
