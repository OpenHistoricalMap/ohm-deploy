FROM golang:1.25.5-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    git \
    make \
    bash \
    nodejs \
    npm

# Clone and build tegola from fork
WORKDIR /build
ENV TEGOLA_GITSHA=b7245bb58f22d8e75076cabe444a445a3798a9b2
RUN git clone https://github.com/OpenHistoricalMap/tegola.git . && git checkout $TEGOLA_GITSHA

# Build arguments for version information
ARG BUILD_PKG="github.com/go-spatial/tegola/internal/build"
RUN echo "Generating UI files..." && \
    go generate ./server && \
    echo "Building tegola binary..." && \
    cd cmd/tegola && \
    go build -mod vendor \
    -ldflags "-w -X '${BUILD_PKG}.Version=${VER}' -X '${BUILD_PKG}.GitRevision=${REVISION}' -X '${BUILD_PKG}.GitBranch=${BRANCH}'" \
    -o /usr/local/bin/tegola

FROM alpine:latest

RUN apk add --no-cache \
    python3 \
    py3-cffi \
    py3-cryptography \
    libffi \
    bash \
    git \
    postgresql-client \
    coreutils \
    jq \
    procps \
    dcron \
    ca-certificates \
    && apk add --no-cache --virtual .build-deps \
    gcc \
    libffi-dev \
    musl-dev \
    openssl-dev \
    python3-dev \
    py3-pip \
    && pip install --break-system-packages --upgrade pip \
    && pip install --break-system-packages awscli mercantile requests boto3 psycopg2-binary \
    && apk del .build-deps \
    && rm -rf /root/.cache /var/cache/apk/*

COPY --from=builder /usr/local/bin/tegola /usr/local/bin/tegola
WORKDIR /app
COPY . .
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/app/start.sh"]
