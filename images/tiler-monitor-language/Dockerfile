FROM python:3.12-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        bash \
        postgresql-client && \
    rm -rf /var/lib/apt/lists/*

# Docker CLI + Compose plugin: the language monitor restarts tiler containers
# via `docker compose` on the hetzner docker host.
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then DOCKER_ARCH="x86_64"; else DOCKER_ARCH="aarch64"; fi && \
    curl -fsSL "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-27.5.1.tgz" | \
    tar xz --strip-components=1 -C /usr/local/bin docker/docker

RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then COMPOSE_ARCH="x86_64"; else COMPOSE_ARCH="aarch64"; fi && \
    mkdir -p /usr/local/lib/docker/cli-plugins && \
    curl -fsSL "https://github.com/docker/compose/releases/download/v2.32.4/docker-compose-linux-${COMPOSE_ARCH}" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

WORKDIR /app

COPY monitor_languages.sh /app/monitor_languages.sh
RUN chmod +x /app/monitor_languages.sh

CMD ["bash", "/app/monitor_languages.sh"]
