FROM ghcr.io/bdon/osmexpress:latest

ENV PATH="/root/.cargo/bin:${PATH}"

RUN apk add --no-cache python3 py3-pip git bash xmlstarlet curl aws-cli

RUN apk add --no-cache --virtual .build-deps build-base patch python3-dev make cmake zlib-dev expat-dev bzip2-dev boost-dev rust cargo && \
    \
    pip install --break-system-packages osmx py3-requests osmium && \
    \
    echo "--- Clonando y modificando osm-cli para OpenHistoricalMap ---" && \
    git clone https://github.com/jake-low/osm-cli.git /tmp/osm-cli && \
    cd /tmp/osm-cli && \
    echo "Cambiando URL en src/replication.rs" && \
    sed -i 's|https://planet.openstreetmap.org/replication/minute|https://s3.amazonaws.com/planet.openhistoricalmap.org/replication/minute|g' src/replication.rs && \
    echo "Cambiando URL en src/main.rs" && \
    sed -i 's|https://www.openstreetmap.org|https://www.openhistoricalmap.org|g' src/main.rs && \
    echo "Compilando osm-cli desde la fuente modificada..." && \
    cargo install --path . && \
    cd / && \
    rm -rf /tmp/osm-cli && \
    \
    apk del .build-deps && \
    apk add make

RUN curl https://mise.jdx.dev/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /app

RUN echo "Update repo 08/08/2025"

RUN git clone https://github.com/OpenHistoricalMap/osmx-adiff-builder.git /app

COPY start.sh .

RUN chmod +x /app/*.sh && chmod +x /app/*.py

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/app/start.sh"]
