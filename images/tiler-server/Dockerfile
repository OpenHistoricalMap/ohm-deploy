FROM gospatial/tegola:v0.21.0

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
    procps

RUN pip install --upgrade pip && pip3 install awscli mercantile

RUN rm -rf /var/cache/apk/* \
    && apk del py3-pip

# Symlink tegola binary for easier access
RUN ln -s /opt/tegola /usr/bin/tegola

COPY ./config /opt/config/
COPY build_config.py /opt/
RUN mkdir /opt/tegola_config
RUN cd /opt/ && python build_config.py \
    --template config/config.template.toml \
    --providers config/providers \
    --output /opt/tegola_config/config.toml

COPY ./tile2bounds.py .
COPY ./*.sh .

ENTRYPOINT ["/bin/bash", "-c"]
CMD ./start.sh
