#!/usr/bin/env bash
workdir="/var/www"
export RAILS_ENV=production

setup_env_vars() {
  echo "Setting up environment variables..."
  #### Setting up the production database
  echo " # Production DB
  production:
    adapter: postgresql
    host: ${POSTGRES_HOST}
    database: ${POSTGRES_DB}
    username: ${POSTGRES_USER}
    password: ${POSTGRES_PASSWORD}
    encoding: utf8" >$workdir/config/database.yml

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
}

####################### Setting up development mode #######################
if [ "$ENVIRONMENT" = "development" ]; then
  # Restore db
  export PGPASSWORD=$POSTGRES_PASSWORD
  curl -o backup.sql $BACKUP_FILE_URL
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -f backup.sql

  # Copy example storage configuration for development mode
  cp $workdir/config/example.storage.yml $workdir/config/storage.yml
  cp /tmp/settings.yml $workdir/config/settings.yml
  cp /tmp/settings.local.yml $workdir/config/settings.local.yml

  # Set up environment variables
  setup_env_vars
  bundle exec bin/yarn install
  bundle exec rails db:migrate --trace
  bundle exec rake jobs:work &
  rails server --log-to-stdout
else
####################### Setting up production mode #######################
  # Set up environment variables for production
  setup_env_vars
  
  #### Run a script to update map styles dynamically
  python3 update_map_styles.py
  
  #### Check database readiness and start the application
  flag=true
  while "$flag" = true; do
    # Wait until the database is ready
    pg_isready -h $POSTGRES_HOST -p 5432 >/dev/null 2>&2 || continue
    flag=false

    # Wait for the server to be available, logging progress
    until $(curl -sf -o /dev/null $SERVER_URL); do
      echo "Waiting to start Rails server..."
      sleep 2
    done &

    #### Compile JavaScript and CSS assets to reflect changes in configuration files
    time bundle exec rake i18n:js:export assets:precompile

    #### Copy required assets for Leaflet OHM TimeSlider
    cp $workdir/public/leaflet-ohm-timeslider-v2/assets/* $workdir/public/assets/

    # Run database migrations
    bundle exec rails db:migrate

    # Start the cgimap service to handle API requests
    ./cgimap.sh
    
    #### Start Apache server in the foreground
    apachectl -k start -DFOREGROUND &

    #### Background job processing loop
    # Restart the `rake jobs:work` process every hour to ensure smooth job execution
    while true; do
      pkill -f "rake jobs:work"
      bundle exec rake jobs:work --trace >> $workdir/log/jobs_work.log 2>&1 &
      sleep 1h
    done
  done
fi