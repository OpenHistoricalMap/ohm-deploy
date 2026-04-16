FROM ghcr.io/maplibre/martin:v0.14.2

USER root

RUN apk add --no-cache \
    python3 \
    py3-psycopg2 \
    postgresql-client \
    nginx \
    curl \
    bash

WORKDIR /app
COPY . .
RUN chmod +x /app/start.sh

ENTRYPOINT ["/bin/bash"]
CMD ["/app/start.sh"]
