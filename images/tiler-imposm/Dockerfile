FROM osgeo/gdal:ubuntu-small-3.2.3

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
    software-properties-common && \
    rm -rf /var/lib/apt/lists/*

RUN add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y python3.9 python3.9-dev python3-pip && \
    rm -rf /var/lib/apt/lists/* && \
    python3 -m pip install pip --upgrade && \
    python3 -m pip install wheel

RUN apt-get update && apt-get install -y postgresql-client && \
    rm -rf /var/lib/apt/lists/*

RUN wget -c https://dl.google.com/go/go1.21.0.linux-amd64.tar.gz -O - | tar -xz -C /usr/local
ENV PATH $PATH:/usr/local/go/bin

RUN git clone https://github.com/OpenHistoricalMap/DateFunctions-plpgsql.git /usr/local/datefunctions

WORKDIR /go
ENV GOPATH /go
RUN git clone https://github.com/omniscale/imposm3.git $GOPATH/src/github.com/omniscale/imposm3

WORKDIR $GOPATH/src/github.com/omniscale/imposm3
RUN git checkout v0.14.0


# Apply fixes or patches (if necessary)
RUN sed -i '/setMaxFileSize/d' cache/ldb_pre_121.go
RUN go install github.com/omniscale/imposm3/cmd/imposm
ENV PATH $PATH:$GOPATH/bin

# Install AWS CLI for downloading files
RUN pip3 install -U setuptools awscli psycopg2
WORKDIR /osm
COPY . .
CMD ["./start.sh"]
