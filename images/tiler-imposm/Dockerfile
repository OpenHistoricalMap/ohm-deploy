FROM ghcr.io/osgeo/gdal:ubuntu-small-3.9.3

RUN apt-get -y update && apt-get install -y \
    g++ \
    libboost-dev \
    libboost-system-dev \
    libboost-filesystem-dev \
    libexpat1-dev \
    zlib1g-dev \
    libbz2-dev \
    libpq-dev \
    libgeos++-dev \
    libproj-dev \
    libleveldb-dev \
    libgeos-dev \
    libprotobuf-dev \
    git-core \
    curl \
    wget \
    unzip \
    ca-certificates \
    software-properties-common \
    python3-pip \
    postgresql-client && \
    rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --no-cache-dir \
    --break-system-packages \
    awscli psycopg2-binary setuptools && \
    rm -rf /root/.cache /var/cache/apk/*

RUN apt-get update && apt-get install -y postgresql-client && \
    rm -rf /var/lib/apt/lists/*

RUN wget -c https://dl.google.com/go/go1.21.9.linux-amd64.tar.gz -O - | tar -xz -C /usr/local
ENV PATH="${PATH}:/usr/local/go/bin"

ENV DATEFUNCTIONS_GITSHA=90d8d0f0daea4c8c5aa62edf440f26e9eb0ab950
RUN git clone https://github.com/OpenHistoricalMap/DateFunctions-plpgsql.git /usr/local/datefunctions && cd /usr/local/datefunctions && git checkout $DATEFUNCTIONS_GITSHA 

WORKDIR /go
ENV GOPATH /go
RUN echo "Version v0.14.2"
RUN git clone https://github.com/omniscale/imposm3.git $GOPATH/src/github.com/omniscale/imposm3

WORKDIR $GOPATH/src/github.com/omniscale/imposm3
RUN git checkout v0.14.2

# Apply fixes or patches (if necessary)
RUN sed -i '/setMaxFileSize/d' cache/ldb_pre_121.go
RUN go install github.com/omniscale/imposm3/cmd/imposm
ENV PATH $PATH:$GOPATH/bin

WORKDIR /osm
COPY . .
CMD ["./start.sh"]
