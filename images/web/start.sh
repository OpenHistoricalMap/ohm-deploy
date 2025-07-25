#!/usr/bin/env bash
workdir="/var/www"
export RAILS_ENV=production

setup_env_vars() {
  #### Setting up the production database
  cat <<EOF > "$workdir/config/database.yml"
production:
  adapter: postgresql
  host: ${POSTGRES_HOST}
  database: ${POSTGRES_DB}
  username: ${POSTGRES_USER}
  password: ${POSTGRES_PASSWORD}
  encoding: utf8
EOF

  ##### Setting up S3 storage
  if [ "$RAILS_STORAGE_SERVICE" == "s3" ]; then
    [[ -z "$RAILS_STORAGE_REGION" || -z "$RAILS_STORAGE_BUCKET" ]] && {
      echo "Error: RAILS_STORAGE_REGION or RAILS_STORAGE_BUCKET not set."
      exit 1
    }

    cat <<EOF >> "$workdir/config/storage.yml"
s3:
  service: S3
  region: '$RAILS_STORAGE_REGION'
  bucket: '$RAILS_STORAGE_BUCKET'
EOF
    echo "S3 storage configuration set successfully."
  fi

  #### Initializing an empty $workdir/config/settings.local.yml file, typically used for development settings
  echo "" > $workdir/config/settings.local.yml

  #### Setting up server_url and server_protocol
  sed -i -e 's/^server_protocol: ".*"/server_protocol: "'$SERVER_PROTOCOL'"/g' $workdir/config/settings.yml
  sed -i -e 's/^server_url: ".*"/server_url: "'$SERVER_URL'"/g' $workdir/config/settings.yml

  ### Setting up website status
  sed -i -e 's/^status: ".*"/status: "'$WEBSITE_STATUS'"/g' $workdir/config/settings.yml

  #### Setting up mail sender
  sed -i -e 's/smtp_address: ".*"/smtp_address: "'$MAILER_ADDRESS'"/g' $workdir/config/settings.yml
  sed -i -e 's/smtp_port: .*/smtp_port: '$MAILER_PORT'/g' $workdir/config/settings.yml
  sed -i -e 's/smtp_domain: ".*"/smtp_domain: "'$MAILER_DOMAIN'"/g' $workdir/config/settings.yml
  sed -i -e 's/smtp_authentication: .*/smtp_authentication: "login"/g' $workdir/config/settings.yml
  sed -i -e 's/smtp_user_name: .*/smtp_user_name: "'$MAILER_USERNAME'"/g' $workdir/config/settings.yml
  sed -i -e 's/smtp_password: .*/smtp_password: "'$MAILER_PASSWORD'"/g' $workdir/config/settings.yml

  ### Setting up oauth id and key for iD editor
  sed -i -e 's/^oauth_application: ".*"/oauth_application: "'$OAUTH_CLIENT_ID'"/g' $workdir/config/settings.yml
  sed -i -e 's/^oauth_key: ".*"/oauth_key: "'$OAUTH_KEY'"/g' $workdir/config/settings.yml

  #### Setting up id key for the website
  sed -i -e 's/^id_application: ".*"/id_application: "'$OPENSTREETMAP_id_key'"/g' $workdir/config/settings.yml

  #### Setup env vars for memcached server
  sed -i -e 's/memcache_servers: \[\]/memcache_servers: "'$OPENSTREETMAP_memcache_servers'"/g' $workdir/config/settings.yml

  #### Setting up nominatim url
  sed -i -e 's/nominatim.openhistoricalmap.org/'$NOMINATIM_URL'/g' $workdir/config/settings.yml

  ## Setting up overpass url
  sed -i -e 's/overpass-api.openhistoricalmap.org/'$OVERPASS_URL'/g' $workdir/config/settings.yml
  sed -i -e 's/overpass-api.de/'$OVERPASS_URL'/g' $workdir/app/views/site/export.html.erb
  sed -i -e 's/overpass-api.de/'$OVERPASS_URL'/g' $workdir/app/assets/javascripts/index/export.js

  # Replace overpass-api.de with $OVERPASS_URL in the public assets, from https://github.com/OpenHistoricalMap/issues/issues/1034
  find "$workdir/public/assets/" -type f -exec sed -i -e "s#overpass-api.de#${OVERPASS_URL}#g" {} +

  ## Setting up OpenStreetMap authentication
  sed -i -e 's/^openstreetmap_auth_id: ".*"/openstreetmap_auth_id: "'$OPENSTREETMAP_AUTH_ID'"/g' $workdir/config/settings.yml
  sed -i -e 's/^openstreetmap_auth_secret: ".*"/openstreetmap_auth_secret: "'$OPENSTREETMAP_AUTH_SECRET'"/g' $workdir/config/settings.yml

  ## Setting up required credentials 
  echo $RAILS_CREDENTIALS_YML_ENC > config/credentials.yml.enc
  echo $RAILS_MASTER_KEY > config/master.key 
  chmod 600 config/credentials.yml.enc config/master.key

  #### Adding doorkeeper_signing_key
  openssl genpkey -algorithm RSA -out private.pem
  chmod 400 /var/www/private.pem
  export DOORKEEPER_SIGNING_KEY=$(cat /var/www/private.pem | sed -e '1d;$d' | tr -d '\n')
  sed -i "s#PRIVATE_KEY#${DOORKEEPER_SIGNING_KEY}#" $workdir/config/settings.yml
}

restore_db() {
  export PGPASSWORD="$POSTGRES_PASSWORD"
  curl -s -o backup.sql "$BACKUP_FILE_URL" || {
    echo "Error: Failed to download backup file."
    exit 1
  }

  psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f backup.sql && \
    echo "Database restored successfully." || \
    { echo "Database restore failed."; exit 1; }
}

start_background_jobs() {
  while true; do
    pkill -f "rake jobs:work"
    bundle exec rake jobs:work --trace >> "$workdir/log/jobs_work.log" 2>&1 &
    echo "Restarted rake jobs at $(date)"
    sleep 1h
  done
}

log_and_tail() {
  local file=$1
  if [ -f "$file" ]; then
    echo "🔹 Logs from: $file"
    tail -F "$file" &
  else
    echo "⚠️ Log file not found: $file"
  fi
}

setup_production() {
  setup_env_vars

  # Update map styles. This line should be removed later, as the configuration should come from the module.
  SERVER_URL_="${SERVER_URL/www./}"
  find /var/www/node_modules/@openhistoricalmap/map-styles/dist/ -type f -name "*.json" -exec sed -i.bak "s|openhistoricalmap.github.io|${SERVER_URL}|g" {} +
  find /var/www/node_modules/@openhistoricalmap/map-styles/dist/ -type f -name "*.json" -exec sed -i.bak "s|http://localhost:8888|https://${SERVER_URL}/map-styles|g" {} +
  find /var/www/node_modules/@openhistoricalmap/map-styles/dist/ -type f -name "*.json" -exec sed -i.bak "s|www.openhistoricalmap.org|${SERVER_URL}|g" {} +
  find /var/www/node_modules/@openhistoricalmap/map-styles/dist/ -type f -name "*.json" -exec sed -i.bak "s|vtiles.openhistoricalmap.org|vtiles.${SERVER_URL_}|g" {} +
  find /var/www/node_modules/@openhistoricalmap/map-styles/dist/ -type f -name "*.json" -exec sed -i.bak "s|vtiles.staging.openhistoricalmap.org|vtiles.${SERVER_URL_}|g" {} +

  # Replace URLs in the public directory
  find "/var/www/public" -type f \( \
      -name "mapstyle.js" -o \
      -name "index.html" -o \
      -name "index-layeroptions-tegola-ohm-*.js" -o \
      -name "application-*.js" -o \
      -name "embed-*.js" -o \
      -name "ohm.style-*.js" -o \
      -name "id-*.js" -o \
      -name "index-*.js" \
  \) | while read -r file; do
    echo "Updating $file"
    sed -i.bak \
      -e "s|openhistoricalmap.github.io|${SERVER_URL}|g" \
      -e "s|http://localhost:8888|https://${SERVER_URL}/map-styles|g" \
      -e "s|www.openhistoricalmap.org|${SERVER_URL}|g" \
      -e "s|vtiles.openhistoricalmap.org|vtiles.${SERVER_URL_}|g" \
      -e "s|vtiles.staging.openhistoricalmap.org|vtiles.${SERVER_URL_}|g" \
      "$file"
  done

  echo "Waiting for PostgreSQL to be ready..."
  until pg_isready -h "$POSTGRES_HOST" -p 5432; do
    sleep 2
  done

  # Create the /passenger-instreg directory if it doesn’t exist. This is required in newer versions of Passenger.
  mkdir -p /var/run/passenger-instreg

  echo "Copying static assets..."
  cp "$workdir/public/leaflet-ohm-timeslider-v2/assets/"* "$workdir/public/assets/"

  echo "Running database migrations..."
  time bundle exec rails db:migrate

  if [ "$EXTERNAL_CGIMAP" == "false" ]; then
    echo "Running cgimap..."
    ./cgimap.sh
  fi

  echo "Logging and tailing logs..."
  # log_and_tail /var/www/log/production.log
  # log_and_tail /var/www/log/jobs_work.log
  log_and_tail /var/log/apache2/error.log
  log_and_tail /var/log/apache2/access.log

  echo "Starting Apache server..."
  start_background_jobs &
  apachectl -k start -DFOREGROUND
}

setup_development() {
  restore_db
  cp "$workdir/config/example.storage.yml" "$workdir/config/storage.yml"
  cp /tmp/settings.yml "$workdir/config/settings.yml"
  setup_env_vars
  bundle exec bin/yarn install
  bundle exec rails db:migrate --trace
  bundle exec rake jobs:work &
  rails server --log-to-stdout
}

####################### Setting up Development or Production mode #######################
if [ "$ENVIRONMENT" = "development" ]; then
  setup_development
else
  setup_production
fi