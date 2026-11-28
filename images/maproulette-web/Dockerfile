# MapRoulette frontend (v4) for OHM, served with nginx.
# Built from the OHM fork, which adds the OHM basemap as the default map style.
FROM node:24-alpine AS builder

ENV MAPROULETTE_FRONTEND_GITSHA=d157f4b5a7474fc041d4891a071e424026da26c8
ENV MAPROULETTE_FRONTEND_URL=https://codeload.github.com/OpenHistoricalMap/maproulette-frontend/tar.gz/${MAPROULETTE_FRONTEND_GITSHA}

WORKDIR /app
RUN wget -qO- ${MAPROULETTE_FRONTEND_URL} | tar -xz --strip-components=1

# The postinstall hook seeds .env from .env.example; env.json gets its defaults from it.
RUN npm ci
ENV NODE_OPTIONS="--max-old-space-size=8192"
RUN npm run build

FROM nginx:1.27-alpine

# jq is used by the entrypoint to merge runtime VITE_* env vars into env.json
RUN apk add --no-cache jq

COPY --from=builder /app/dist /var/www/maproulette
COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY 40-maproulette-env.sh /docker-entrypoint.d/40-maproulette-env.sh
RUN chmod +x /docker-entrypoint.d/40-maproulette-env.sh

ENV MR_API_URL=http://localhost:9000
EXPOSE 80
