FROM debian:bookworm-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y gcc g++ make cmake \
    libfcgi-dev libxml2-dev libmemcached-dev libbrotli-dev \
    libboost-program-options-dev libcrypto++-dev libyajl-dev \
    libpqxx-dev zlib1g-dev libfmt-dev \
    postgresql-15 postgresql-server-dev-all dpkg-dev file ca-certificates git \
    --no-install-recommends && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
    
# Clone application.
ENV CGIMAP_GITSHA=01e33669bfee17d55849d6f731a174b8058ca630
RUN git clone https://github.com/zerebubuth/openstreetmap-cgimap.git /app \
&& git checkout $CGIMAP_GITSHA

ARG JOBS=1
ARG BUILD_TESTING=OFF
RUN mkdir build && cd build && \
    CXXFLAGS="-fstack-protector-strong -Wformat -Werror=format-security -Wdate-time -D_FORTIFY_SOURCE=2" cmake .. \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=${BUILD_TESTING} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCGIMAP_COPYRIGHT_MESSAGE="OpenHistoricalMap is dedicated to the public domain except where otherwise noted." \
    -DCGIMAP_ATTRIBUTION_MESSAGE="https://www.openhistoricalmap.org/copyright" \
    -DCGIMAP_LICENSE_MESSAGE="https://creativecommons.org/public-domain/cc0/" && \
    make -j${JOBS} && \
    cmake --build . -t package

FROM debian:bookworm-slim

COPY --from=builder /app/build/*.deb /app_deb/

RUN apt-get update -qq && \
    apt install --no-install-recommends -y /app_deb/*.deb postgresql-client procps && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd -g 61000 cgimap && \
    useradd -g 61000 -l -M -s /bin/false -u 61000 cgimap

EXPOSE 8000

COPY start.sh liveness.sh /app/

RUN chmod +x /app/start.sh /app/liveness.sh

CMD ["/app/start.sh"]
