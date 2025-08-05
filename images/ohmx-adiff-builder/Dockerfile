FROM ghcr.io/bdon/osmexpress:latest

# 1. Install permanent runtime dependencies: python3 and pip
RUN apk add --no-cache python3 py3-pip git bash

RUN apk add --no-cache --virtual .build-deps build-base patch python3-dev && \
    pip install --break-system-packages osmx xmlstarlet && \
    apk del .build-deps

WORKDIR /app

ENV OSMX_ADIFF_BUILDER fe4b3b5c101bb2c3af1187356cdde07015a1a3ed
RUN git clone https://github.com/OSMCha/osmx-adiff-builder.git /app &&  cd /app && git checkout $OSMX_ADIFF_BUILDER && rm -rf .git


# 4. Copy your custom start script
COPY start.sh .

# 5. Set execute permissions on all the scripts
RUN chmod +x /app/*.sh && chmod +x /app/*.py

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/app/start.sh"]