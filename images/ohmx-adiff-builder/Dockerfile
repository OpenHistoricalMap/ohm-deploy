FROM ghcr.io/bdon/osmexpress:045a515132e91a3679ce3df27329937c9b8b221a

ENV PATH="/root/.cargo/bin:${PATH}"

RUN apk add --no-cache python3 py3-pip git bash curl aws-cli py3-lxml make libxml2

RUN apk add --no-cache --virtual .build-deps \
      build-base patch python3-dev cmake zlib-dev expat-dev bzip2-dev boost-dev \
      capnproto-dev libxml2-dev pkgconfig && \
    \
    pip install --break-system-packages osmx requests osmium && \
    \
    # Alpine's rust/cargo lag behind crate MSRVs (osmpbf/home now need rustc 1.88+),
    # so pull a current stable toolchain via rustup instead of the apk packages.
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --profile minimal --default-toolchain stable && \
    \
    echo "--- Build osm-cli (jake-low) with OpenHistoricalMap replication URLs ---" && \
    git clone https://github.com/jake-low/osm-cli.git /tmp/osm-cli && \
    cd /tmp/osm-cli && \
    sed -i 's|https://planet.openstreetmap.org/replication/minute|https://s3.amazonaws.com/planet.openhistoricalmap.org/replication/minute|g' src/replication.rs && \
    sed -i 's|https://www.openstreetmap.org|https://www.openhistoricalmap.org|g' src/main.rs && \
    cargo install --root /usr/local --path . && \
    cd / && rm -rf /tmp/osm-cli && \
    \
    echo "--- Build osmx-rs (jake-low) for augmented-diff --split ---" && \
    cargo install --root /usr/local --git https://github.com/jake-low/osmx-rs.git osmx-rs && \
    \
    # Binaries now live in /usr/local/bin, so the whole toolchain can go.
    rustup self uninstall -y && \
    apk del .build-deps

RUN curl https://mise.jdx.dev/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /app

# Pipeline scripts come from OSMCha/osmx-adiff-builder (Rust path), customized
# for OpenHistoricalMap and copied in directly instead of cloned.
COPY scripts/*.sh scripts/*.py scripts/*.mk /app/

RUN chmod +x /app/*.sh && chmod +x /app/*.py

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/app/start.sh"]
