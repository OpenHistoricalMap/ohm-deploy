FROM python:3.12-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        bash \
        ca-certificates \
        postgresql-client && \
    rm -rf /var/lib/apt/lists/*

# kubectl: the language monitor recreates mviews (exec into imposm) and restarts
# Martin (rollout restart) when new languages appear.
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then KUBE_ARCH="amd64"; else KUBE_ARCH="arm64"; fi && \
    curl -fsSL "https://dl.k8s.io/release/v1.30.5/bin/linux/${KUBE_ARCH}/kubectl" -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

WORKDIR /app

COPY monitor_languages_k8s.sh /app/monitor_languages_k8s.sh
RUN chmod +x /app/monitor_languages_k8s.sh

CMD ["bash", "/app/monitor_languages_k8s.sh"]
