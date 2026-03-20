FROM python:3.12-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        bash \
        postgresql-client && \
    rm -rf /var/lib/apt/lists/*

# Install Docker CLI from official static binaries
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then DOCKER_ARCH="x86_64"; else DOCKER_ARCH="aarch64"; fi && \
    curl -fsSL "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-27.5.1.tgz" | \
    tar xz --strip-components=1 -C /usr/local/bin docker/docker

# Install Docker Compose plugin
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then COMPOSE_ARCH="x86_64"; else COMPOSE_ARCH="aarch64"; fi && \
    mkdir -p /usr/local/lib/docker/cli-plugins && \
    curl -fsSL "https://github.com/docker/compose/releases/download/v2.32.4/docker-compose-linux-${COMPOSE_ARCH}" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

WORKDIR /app

# Install Python dependencies for pipeline monitor
COPY pipeline-monitor/requirements.txt /app/pipeline-monitor/requirements.txt
RUN pip install --no-cache-dir -r /app/pipeline-monitor/requirements.txt

# Copy application code
COPY language-monitor/ /app/language-monitor/
COPY pipeline-monitor/ /app/pipeline-monitor/
COPY entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/entrypoint.sh /app/language-monitor/monitor_languages.sh

EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=30s \
    CMD curl -f http://localhost:8001/health || exit 1

CMD ["/app/entrypoint.sh"]
