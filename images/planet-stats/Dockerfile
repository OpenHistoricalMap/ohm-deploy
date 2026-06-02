FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    UV_LINK_MODE=copy \
    PATH="/root/.local/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git bash \
        s3cmd osmium-tool \
        libgeos-c1v5 libproj25 libexpat1 \
        build-essential libgeos-dev libproj-dev libexpat1-dev libbz2-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

WORKDIR /app

ENV GITSHA_PLANET_STATS=7752abdf885ea5bfb4ea0f106ad5c50940b8007e
# Fork of danvk/ohm with the planet-stats fixes (state.txt fetch, first-run safe). OHM #1350.
RUN git clone https://github.com/Rub21/ohm.git /app && git checkout $GITSHA_PLANET_STATS
RUN uv sync --frozen || uv sync

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh /app/*.sh

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/app/start.sh"]
