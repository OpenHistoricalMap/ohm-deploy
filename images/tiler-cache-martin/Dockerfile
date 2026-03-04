FROM python:3.12-alpine

WORKDIR /app

COPY config/ ./config/
COPY scripts/ ./scripts/

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health').read()" || exit 1

CMD ["python3", "/app/scripts/watch_and_purge.py"]
