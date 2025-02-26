FROM gospatial/tegola:v0.21.2

RUN apk --no-cache add \
    gcc \
    libffi-dev \
    python3 \
    py3-pip \
    py3-cffi \
    py3-cryptography \
    linux-headers \
    musl-dev \
    openssl-dev \
    bash \
    git \
    postgresql-client \
    coreutils \
    jq \
    procps \
    dcron

RUN pip install --upgrade pip && pip3 install awscli mercantile

RUN rm -rf /var/cache/apk/* \
    && apk del py3-pip

# Symlink tegola binary for easier access
RUN ln -s /opt/tegola /usr/bin/tegola

COPY ./config /opt/config/
COPY build_config.py /opt/
RUN mkdir /opt/tegola_config
RUN cd /opt/ && python build_config.py \
    --output=/opt/tegola_config/config.toml \
    --provider_names \
    "land,\
    admin_boundaries_lines,\
    admin_boundaries.centroids,\
    admin_boundaries_maritime,\
    place_areas,\
    place_points,\
    water_areas,\
    water_areas.centroids,\
    water_lines,\
    transport_areas,\
    transport_associated_streets,\
    transport_lines,\
    transport_points,\
    route_lines,\
    amenity_areas,\
    amenity_areas.centroids,\
    amenity_points,\
    buildings,\
    buildings.centroids,\
    buildings_points,\
    landuse_areas,\
    landuse_areas.centroids,\
    landuse_lines,\
    landuse_points,\
    other_areas,\
    other_areas.centroids,\
    other_lines,\
    other_points"

COPY ./*.py .
COPY ./*.sh .

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/opt/start.sh"]
