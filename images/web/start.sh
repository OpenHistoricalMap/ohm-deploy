#!/usr/bin/env bash
workdir="/var/www"
export RAILS_ENV=production
#### Because we can not set up many env variable in build process, we are going to process here!

#### Setting up the production database
echo " # Production DB
production:
  adapter: postgresql
  host: ${POSTGRES_HOST}
  database: ${POSTGRES_DB}
  username: ${POSTGRES_USER}
  password: ${POSTGRES_PASSWORD}
  encoding: utf8" >$workdir/config/database.yml

#### Setting up S3 storage
if [ "$RAILS_STORAGE_SERVICE" == "s3" ]; then
  if [ -z "$RAILS_STORAGE_REGION" ] || [ -z "$RAILS_STORAGE_BUCKET" ]; then
    echo "Error: Missing RAILS_STORAGE_REGION or RAILS_STORAGE_BUCKET environment variable."
    exit 1
  fi

  echo "
  s3:
    service: S3
    region: '$RAILS_STORAGE_REGION'
    bucket: '$RAILS_STORAGE_BUCKET'" >> $workdir/config/storage.yml

  sed -i -e 's/^avatar_storage: ".*"/avatar_storage: "'$RAILS_STORAGE_SERVICE'"/g' $workdir/config/settings.yml
  sed -i -e 's/^trace_file_storage: ".*"/trace_file_storage: "'$RAILS_STORAGE_SERVICE'"/g' $workdir/config/settings.yml
  sed -i -e 's/^trace_image_storage: ".*"/trace_image_storage: "'$RAILS_STORAGE_SERVICE'"/g' $workdir/config/settings.yml
  sed -i -e 's/^trace_icon_storage: ".*"/trace_icon_storage: "'$RAILS_STORAGE_SERVICE'"/g' $workdir/config/settings.yml
  sed -i "s/config.active_storage.service = :local/config.active_storage.service = :${RAILS_STORAGE_SERVICE}/g" $workdir/config/environments/production.rb

else
  echo "RAILS_STORAGE_SERVICE is not set to 's3', skipping configuration."
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
sed -i -e 's/nominatim-api.openhistoricalmap.org/'$NOMINATIM_URL'/g' $workdir/config/settings.yml

## Setting up overpass url
sed -i -e 's/overpass-api.openhistoricalmap.org/'$OVERPASS_URL'/g' $workdir/config/settings.yml
sed -i -e 's/overpass-api.de/'$OVERPASS_URL'/g' $workdir/app/views/site/export.html.erb
sed -i -e 's/overpass-api.de/'$OVERPASS_URL'/g' $workdir/app/assets/javascripts/index/export.js

## Setting up required credentials 
echo $RAILS_CREDENTIALS_YML_ENC > config/credentials.yml.enc
echo $RAILS_MASTER_KEY > config/master.key 
chmod 600 config/credentials.yml.enc config/master.key

#### Adding doorkeeper_signing_key
openssl genpkey -algorithm RSA -out private.pem
chmod 400 /var/www/private.pem
export DOORKEEPER_SIGNING_KEY=$(cat /var/www/private.pem | sed -e '1d;$d' | tr -d '\n')
sed -i "s#PRIVATE_KEY#${DOORKEEPER_SIGNING_KEY}#" $workdir/config/settings.yml

#### Updating map-styles
python3 update_map_styles.py

#### Checking if db is already up and start the app
flag=true
while "$flag" = true; do
  pg_isready -h $POSTGRES_HOST -p 5432 >/dev/null 2>&2 || continue
  flag=false
  # Print the log while compiling the assets
  until $(curl -sf -o /dev/null $SERVER_URL); do
    echo "Waiting to start rails ports server..."
    sleep 2
  done &

  # Enable assets:precompile
  time bundle exec rake i18n:js:export assets:precompile

  # Since leaflet-ohm-timeslider.css points directly to the svg files, they need to be copied to the public/assets directory.
  cp $workdir/public/leaflet-ohm-timeslider-v2/assets/* $workdir/public/assets/

  bundle exec rails db:migrate

  # Start cgimap
  ./cgimap.sh
  
  apachectl -k start -DFOREGROUND &
  # Loop to restart rake job every hour
  while true; do
    pkill -f "rake jobs:work"
    bundle exec rake jobs:work --trace >> $workdir/log/jobs_work.log 2>&1 &
    sleep 1h
  done
done
