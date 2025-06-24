FROM docker:cli

RUN apk add --no-cache \
    bash \
    curl \
    postgresql-client \
    docker-cli-compose

WORKDIR /app

COPY monitor_languages.sh .
RUN chmod +x monitor_languages.sh

CMD ["bash", "monitor_languages.sh"]
