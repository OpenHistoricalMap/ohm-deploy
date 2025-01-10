FROM ruby:3.3.0 AS cgimap-builder

ENV DEBIAN_FRONTEND=noninteractive
ENV CGIMAP_REPO="https://github.com/zerebubuth/openstreetmap-cgimap.git"
ENV CGIMAP_GITSHA="26cd7fa10affe5dbd13dbe16de34421059f53f18"
ENV CGIMAP_PATH="/tmp/openstreetmap-cgimap"

# Install dependencies required to build cgimap
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    cmake \
    libxml2-dev \
    libpqxx-dev \
    libfcgi-dev \
    zlib1g-dev \
    libbrotli-dev \
    libboost-program-options-dev \
    libfmt-dev \
    libmemcached-dev \
    libcrypto++-dev \
    libargon2-dev \
    libyajl-dev \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Clone cgimap repository, checkout the desired commit, and build
RUN git clone -b master "$CGIMAP_REPO" "$CGIMAP_PATH" \
 && cd "$CGIMAP_PATH" \
 && git checkout "$CGIMAP_GITSHA" \
 && rm -rf .git \
 && mkdir build && cd build \
 && cmake .. \
 && cmake --build .

###############################################################################
# 2) BASE STAGE - Node, Yarn, Postgres client, cgimap runtime
###############################################################################
FROM ruby:3.3.0

ENV DEBIAN_FRONTEND=noninteractive

# Install Node, Yarn, PostgreSQL client, and other runtime dependencies
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    curl \
    postgresql-client \
    libpq-dev \
    libfcgi0ldbl \
    zlib1g \
    libbrotli1 \
    libboost-program-options1.74.0 \
    libfmt7 \
    libmemcached11 \
    libcrypto++8 \
    libargon2-1 \
    libyajl2 \
    software-properties-common \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Install Node & Yarn from upstream repositories
RUN curl -sL https://deb.nodesource.com/setup_18.x | bash - \
 && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
 && echo "deb https://dl.yarnpkg.com/debian/ stable main" \
    | tee /etc/apt/sources.list.d/yarn.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends nodejs yarn \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Copy the compiled cgimap binary from the builder stage
COPY --from=cgimap-builder /tmp/openstreetmap-cgimap/build/openstreetmap-cgimap /usr/local/bin/openstreetmap-cgimap
RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/local_libs.conf && ldconfig
