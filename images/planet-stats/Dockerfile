FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    UV_LINK_MODE=copy \
    PATH="/root/.local/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git bash \
        s3cmd \
        libgeos-c1v5 libproj25 libexpat1 \
        build-essential libgeos-dev libproj-dev libexpat1-dev libbz2-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

WORKDIR /app

RUN git clone https://github.com/danvk/ohm.git /app
RUN uv sync --frozen || uv sync

COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh /app/*.sh

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/app/run.sh"]
