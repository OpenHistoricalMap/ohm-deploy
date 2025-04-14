FROM ruby:3.3-slim

ENV DEBIAN_FRONTEND=noninteractive \
    workdir=/var/www

WORKDIR $workdir

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git curl gnupg libarchive-dev \
    zlib1g-dev libcurl4-openssl-dev \
    apache2 apache2-dev libapache2-mod-passenger libapache2-mod-fcgid libapr1-dev libaprutil1-dev \
    build-essential postgresql-client && \
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs libpq-dev libxml2-dev libyaml-dev && \
    if ! command -v yarn >/dev/null 2>&1; then npm install -g yarn; fi && \
    npm install -g svgo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Passenger
RUN a2enmod passenger

# Clone OHM Website
ENV OPENHISTORICALMAP_WEBSITE_GITSHA=fb2292b81faefb5ce7c704ddb0c57814e1c4cd7a
RUN rm -rf $workdir/*
RUN git clone https://github.com/OpenHistoricalMap/ohm-website.git $workdir && \
    cd $workdir && git checkout $OPENHISTORICALMAP_WEBSITE_GITSHA && rm -rf .git

 
# Install Ruby/Node dependencies
RUN gem install bundler && bundle install && \
    yarn install && \
    bundle exec rake yarn:install

RUN cp config/example.database.yml config/database.yml && \
    cp config/example.storage.yml config/storage.yml && \
    touch config/settings.local.yml && \
    chmod 600 config/database.yml

RUN rm -f config/credentials.yml.enc && \
    export RAILS_MASTER_KEY=$(openssl rand -hex 16) && \
    export SECRET_KEY_BASE=$(bundle exec rails secret) && \
    echo $RAILS_MASTER_KEY > config/master.key && \
    EDITOR="echo" RAILS_MASTER_KEY=$RAILS_MASTER_KEY rails credentials:edit && \
    RAILS_MASTER_KEY=$RAILS_MASTER_KEY rails runner "\
      require 'active_support/encrypted_configuration'; \
      require 'yaml'; \
      creds = ActiveSupport::EncryptedConfiguration.new(\
        config_path: 'config/credentials.yml.enc', \
        key_path: 'config/master.key', \
        env_key: 'RAILS_MASTER_KEY', \
        raise_if_missing_key: true \
      ); \
      credentials = { secret_key_base: '$SECRET_KEY_BASE' }; \
      creds.write(credentials.to_yaml); \
      puts 'Credentials configured correctly.'"

# Precompile assets
RUN bundle exec rake i18n:js:export && \
    bundle exec rake assets:precompile
RUN ln -s /tmp /var/www/tmp

# Apache config
COPY config/production.conf /etc/apache2/sites-available/production.conf
RUN a2enmod headers setenvif proxy proxy_http proxy_fcgi fcgid rewrite lbmethod_byrequests passenger && \
    a2dissite 000-default && \
    a2ensite production && \
    echo "ServerName $(cat /etc/hostname)" >> /etc/apache2/apache2.conf

RUN apache2ctl configtest
RUN chown -R www-data: $workdir

# Map styles
RUN mkdir -p public/map-styles
COPY update_map_styles.py $workdir/

# Leaflet timeslider assets
ENV LEAFLET_OHM_TIMESLIDER_V2=dd0acbdc9432fae6a4d09a17a4848c391e5064f0
RUN git clone https://github.com/OpenHistoricalMap/leaflet-ohm-timeslider-v2.git $workdir/public/leaflet-ohm-timeslider-v2 && \
    cd $workdir/public/leaflet-ohm-timeslider-v2 && \
    git checkout $LEAFLET_OHM_TIMESLIDER_V2 && \
    rm -rf .git && \
    chmod 777 -R assets/ && \
    cp decimaldate.* $workdir/app/assets/javascripts/ && \
    cp leaflet-ohm-timeslider.* $workdir/app/assets/javascripts/ && \
    cp leaflet-ohm-timeslider.* $workdir/app/assets/stylesheets/ && \
    cp assets/* $workdir/app/assets/images/


COPY config/settings.yml $workdir/config/
COPY start.sh liveness.sh $workdir/
RUN chmod +x $workdir/*.sh

CMD ["./start.sh"]
