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

#### Setting up server_url and server_protocol
sed -i -e 's/server_url: "openhistoricalmap.example.com"/server_url: "'$SERVER_URL'"/g' $workdir/config/settings.local.yml
sed -i -e 's/server_protocol: "http"/server_protocol: "'$SERVER_PROTOCOL'"/g' $workdir/config/settings.local.yml

### Setting up website status
sed -i "s/online/$WEBSITE_STATUS/g" $workdir/config/settings.yml

#### Setting up mail sender
sed -i -e 's/smtp_address: "localhost"/smtp_address: "'$MAILER_ADDRESS'"/g' $workdir/config/settings.local.yml
sed -i -e 's/smtp_domain: "localhost"/smtp_domain: "'$MAILER_DOMAIN'"/g' $workdir/config/settings.local.yml
sed -i -e 's/smtp_enable_starttls_auto: false/smtp_enable_starttls_auto: true/g' $workdir/config/settings.local.yml
sed -i -e 's/smtp_authentication: null/smtp_authentication: "login"/g' $workdir/config/settings.local.yml
sed -i -e 's/smtp_user_name: null/smtp_user_name: "'$MAILER_USERNAME'"/g' $workdir/config/settings.local.yml
sed -i -e 's/smtp_password: null/smtp_password: "'$MAILER_PASSWORD'"/g' $workdir/config/settings.local.yml
sed -i -e 's/openstreetmap@example.com/'$MAILER_FROM'/g' $workdir/config/settings.local.yml
sed -i -e 's/smtp_port: 25/smtp_port: '$MAILER_PORT'/g' $workdir/config/settings.local.yml

#### Setting up id key fro the website
sed -i -e 's/id_application: ""/id_application: "'$OPENSTREETMAP_id_key'"/g' $workdir/config/settings.local.yml
sed -i -e 's/#id_application: ""/id_application: "'$OPENSTREETMAP_id_key'"/g' $workdir/config/settings.yml

#### Setting up oauth id and key for iD editor
sed -i -e 's/OAUTH_CLIENT_ID/'$OAUTH_CLIENT_ID'/g' $workdir/config/settings.local.yml
sed -i -e 's/OAUTH_KEY/'$OAUTH_KEY'/g' $workdir/config/settings.local.yml
sed -i -e 's/# oauth_application: "OAUTH_CLIENT_ID"/oauth_application: "'$OAUTH_CLIENT_ID'"/g' $workdir/config/settings.yml
sed -i -e 's/# oauth_key: "OAUTH_CLIENT_ID"/oauth_key: "'$OAUTH_KEY'"/g' $workdir/config/settings.yml

#### Setup env vars for memcached server
sed -i -e 's/memcache_servers: \[\]/memcache_servers: "'$OPENSTREETMAP_memcache_servers'"/g' $workdir/config/settings.local.yml

#### Setting up nominatim url
sed -i -e 's/nominatim.openhistoricalmap.org/'$NOMINATIM_URL'/g' $workdir/config/settings.local.yml

#### Setting up overpass url
sed -i -e 's/overpass-api.de/'$OVERPASS_URL'/g' $workdir/config/settings.local.yml
sed -i -e 's/overpass-api.de/'$OVERPASS_URL'/g' $workdir/app/views/site/export.html.erb
sed -i -e 's/overpass-api.de/'$OVERPASS_URL'/g' $workdir/app/assets/javascripts/index/export.js

#### Adding doorkeeper_signing_key
openssl genpkey -algorithm RSA -out private.pem
chmod 400 /var/www/private.pem
export DOORKEEPER_SIGNING_KEY=$(cat /var/www/private.pem | sed -e '1d;$d' | tr -d '\n')
sed -i "s#PRIVATE_KEY#${DOORKEEPER_SIGNING_KEY}#" $workdir/config/settings.local.yml

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

  # Enable assets:precompile, to take lates changes for assets in $workdir/config/settings.local.yml.
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
