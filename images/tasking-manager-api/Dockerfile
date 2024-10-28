ARG DEBIAN_IMG_TAG=slim-bookworm
ARG PYTHON_IMG_TAG=3.10

FROM docker.io/python:${PYTHON_IMG_TAG}-${DEBIAN_IMG_TAG} as base
ARG APP_VERSION=0.1.0
ARG DOCKERFILE_VERSION=0.5.0
ARG MAINTAINER=sysadmin@hotosm.org
LABEL org.hotosm.tasks.app-version="${APP_VERSION}" \
    org.hotosm.tasks.debian-img-tag="${DEBIAN_IMG_TAG}" \
    org.hotosm.tasks.python-img-tag="${PYTHON_IMG_TAG}" \
    org.hotosm.tasks.dockerfile-version="${DOCKERFILE_VERSION}" \
    org.hotosm.tasks.maintainer="${MAINTAINER}" \
    org.hotosm.tasks.api-port="5000"
# Fix timezone (do not change - see issue #3638)
ENV TZ UTC
# Add non-root user, permissions, init log dir
RUN useradd --uid 9000 --create-home --home /home/appuser --shell /bin/false appuser

FROM base as extract-deps
RUN python -m pip install --no-cache-dir --upgrade pip
WORKDIR /opt/python
COPY pyproject.toml pdm.lock README.md /opt/python/
RUN python -m pip install --no-cache-dir pdm==2.7.4
RUN pdm export --prod --without-hashes > requirements.txt

FROM base as build
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
    build-essential \
    postgresql-server-dev-15 \
    python3-dev \
    libffi-dev \
    libgeos-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/python
COPY --from=extract-deps \
    /opt/python/requirements.txt /opt/python/
USER appuser:appuser
RUN python -m pip install --user --no-warn-script-location \
    --no-cache-dir -r /opt/python/requirements.txt

FROM base as runtime
WORKDIR /usr/src/app
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONFAULTHANDLER=1 \
    PATH="/home/appuser/.local/bin:$PATH" \
    PYTHON_LIB="/home/appuser/.local/lib/python${PYTHON_IMG_TAG}/site-packages" \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
    postgresql-client git libgeos3.11.1 proj-bin && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
COPY --from=build \
    /home/appuser/.local \
    /home/appuser/.local
USER root
RUN git clone https://github.com/OpenHistoricalMap/tasking-manager.git /usr/src/app && \
    chown -R appuser:appuser /usr/src/app
USER appuser:appuser
RUN cd /usr/src/app && git checkout -f 506bae7b5fecc2b0b6038d21c137ff6eb1bf5e5e

FROM runtime as debug
RUN python -m pip install --user --no-warn-script-location \
    --no-cache-dir debugpy==1.6.7
EXPOSE 5678/tcp
CMD ["python", "-m", "debugpy", "--wait-for-client", "--listen", "0.0.0.0:5678", \
    "-m", "gunicorn", "-c", "python:backend.gunicorn", "manage:application", \
    "--reload", "--log-level", "error"]

FROM runtime as prod
USER root
RUN apt-get update && \
    apt-get install -y curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN python -m compileall -q .
EXPOSE 5000/tcp
USER appuser:appuser
CMD ["gunicorn", "-c", "python:backend.gunicorn", "manage:application", \
    "--workers", "1", "--log-level", "error"]
    