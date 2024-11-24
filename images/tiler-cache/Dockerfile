FROM ghcr.io/openhistoricalmap/tiler-server:0.0.1-0.dev.git.1734.h5b4d15d

RUN apk update && apk add --no-cache \
    proj \
    proj-dev \
    gdal \
    gdal-dev \
    geos \
    geos-dev \
    python3-dev \
    py3-pip \
    build-base \
    proj-util \
    git

# Ensure PROJ_DIR and PATH are set
ENV PROJ_DIR=/usr
ENV PATH="/usr/share/proj:${PATH}"

# Upgrade pip
RUN python3 -m pip install --upgrade pip

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY tiler-purge ./tiler-purge
COPY tiler-seed ./tiler-seed
COPY start.sh .
RUN chmod +x ./start.sh

ENTRYPOINT ["/app/start.sh"]