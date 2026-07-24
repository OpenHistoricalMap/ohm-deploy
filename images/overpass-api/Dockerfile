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
# Build from the b1tw153 fork (v0.7.62.11), which includes the security fixes
# from drolbr/Overpass-API PRs #796 and #797 that are not merged upstream yet.
ENV OVERPASS_API_GITSHA=dc87da313256ad0fc81370793608e0d989b4714a
ENV OVERPASS_API_URL=https://github.com/b1tw153/Overpass-API/archive/${OVERPASS_API_GITSHA}.tar.gz
ADD ${OVERPASS_API_URL} /tmp/src.tar.gz

WORKDIR /tmp/src
RUN tar -x -z --strip-components 1 -f /tmp/src.tar.gz

# The GitHub archive keeps the sources under src/, unlike the release tarball
WORKDIR /tmp/src/src

# Use OHM copyright and URLs instead of OSM defaults. See issue #558.
RUN sed -i \
        -e 's|www\.openstreetmap\.org/browse/|www.openhistoricalmap.org/|g' \
        -e 's|www\.openstreetmap\.org|www.openhistoricalmap.org|g' \
        -e 's|made available under ODbL|made available under CC0|g' \
        overpass_api/frontend/basic_formats.cc \
        overpass_api/output_formats/output_json.cc \
        overpass_api/output_formats/output_xml.cc \
        overpass_api/dispatch/osm3s_query.cc \
        overpass_api/output_formats/output_custom_factory.cc

RUN autoreconf -f -i \
    && CXXFLAGS='-O2' CFLAGS='-O2' ./configure --prefix=/app --enable-lz4 \
    && make -j "$(nproc)" \
    && make install \
    && mkdir -p /app/etc \
    && cp -r /tmp/src/src/rules /app/etc/rules \
    && rm -rf /tmp/src /tmp/src.tar.gz

ARG WIKTORN_TAG
FROM wiktorn/overpass-api:v0.7.62.9

COPY --from=builder /app/bin/     /app/bin/
COPY --from=builder /app/cgi-bin/ /app/cgi-bin/
COPY --from=builder /app/etc/     /app/etc/

RUN apt-get update \
    && apt-get install --no-install-recommends --no-install-suggests -y \
        less \
        procps \
    && rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh fix-permissions.sh /app/
RUN chmod +x /app/docker-entrypoint.sh /app/fix-permissions.sh

EXPOSE 80

ENTRYPOINT ["/app/docker-entrypoint.sh"]
