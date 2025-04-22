FROM gospatial/tegola:v0.21.2

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
    && apk add --no-cache --virtual .build-deps \
    gcc \
    libffi-dev \
    musl-dev \
    openssl-dev \
    python3-dev \
    py3-pip \
    && pip install --upgrade pip \
    && pip install awscli mercantile requests boto3 \
    && apk del .build-deps \
    && rm -rf /root/.cache /var/cache/apk/*

# Symlink tegola binary for easier access
RUN ln -s /opt/tegola /usr/bin/tegola
COPY . /opt/
COPY ./*.sh .

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/opt/start.sh"]