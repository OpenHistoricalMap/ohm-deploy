# osmcoastline over the OHM planet. Builds land-polygons-split-3857.zip with the
# OHM coastlines and loads it into the tiler DB.
# noble = Ubuntu 24.04 (Python 3.12), which has osmium wheels
FROM ubuntu:24.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl zip unzip jq \
    osmcoastline osmium-tool gdal-bin postgresql-client \
    python3 python3-venv \
 && rm -rf /var/lib/apt/lists/* \
 && python3 -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir osmium==4.0.2 awscli==1.36.40 \
 && osmcoastline --version
ENV PATH=/opt/venv/bin:$PATH \
    DATA_DIR=/data
WORKDIR /app
COPY scripts/ /app/scripts/
RUN chmod +x /app/scripts/*.sh
CMD ["/app/scripts/run.sh"]
