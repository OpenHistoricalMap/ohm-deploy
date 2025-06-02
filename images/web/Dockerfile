FROM ruby:3.3-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    workdir=/var/www

WORKDIR $workdir

# Install base build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git curl gnupg build-essential \
    libarchive-dev zlib1g-dev libcurl4-openssl-dev \
    apache2 apache2-dev libapache2-mod-passenger libapache2-mod-fcgid libapr1-dev libaprutil1-dev \
    postgresql-client libpq-dev libxml2-dev libyaml-dev \
    pngcrush optipng advancecomp pngquant jhead jpegoptim gifsicle libjpeg-progs \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g yarn svgo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN a2enmod passenger

# Clone OHM Website
ENV OPENHISTORICALMAP_WEBSITE_GITSHA=6129d7657859a3a49d7398a1679ab6e867a6e28a
RUN rm -rf $workdir/* && \
    git clone https://github.com/OpenHistoricalMap/ohm-website.git $workdir && \
    cd $workdir && \
    git checkout $OPENHISTORICALMAP_WEBSITE_GITSHA && \
    echo 'merge PRs 288 & 290' && \
    git fetch && rm -rf .git

# Install Ruby/Node dependencies
RUN gem install bundler && \
    bundle install && \
    yarn install && \
    bundle exec rake yarn:install

# Dummy config for precompile
RUN cp config/example.database.yml config/database.yml && \
    cp config/example.storage.yml config/storage.yml && \
    touch config/settings.local.yml && \
    chmod 600 config/database.yml

# Create dummy credentials
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

# Leaflet timeslider assets
ENV LEAFLET_OHM_TIMESLIDER_V2=dd0acbdc9432fae6a4d09a17a4848c391e5064f0
RUN git clone https://github.com/OpenHistoricalMap/leaflet-ohm-timeslider-v2.git public/leaflet-ohm-timeslider-v2 && \
    cd public/leaflet-ohm-timeslider-v2 && \
    git checkout $LEAFLET_OHM_TIMESLIDER_V2 && \
    rm -rf .git && \
    cp decimaldate.* $workdir/app/assets/javascripts/ && \
    cp leaflet-ohm-timeslider.* $workdir/app/assets/javascripts/ && \
    cp leaflet-ohm-timeslider.* $workdir/app/assets/stylesheets/ && \
    cp assets/* $workdir/app/assets/images/

FROM ruby:3.3-slim

ENV DEBIAN_FRONTEND=noninteractive \
    workdir=/var/www

WORKDIR $workdir

# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2 libapache2-mod-passenger libapache2-mod-fcgid \
    libpq5 libxml2 libyaml-0-2 libarchive13 file libgd-dev \
    postgresql-client curl libvips \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=builder /var/www /var/www
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Symlink tmp for Passenger
RUN ln -s /tmp /var/www/tmp

# Apache configuration
COPY config/production.conf /etc/apache2/sites-available/production.conf
RUN a2enmod headers setenvif proxy proxy_http proxy_fcgi fcgid rewrite lbmethod_byrequests passenger && \
    a2dissite 000-default && \
    a2ensite production && \
    echo "ServerName localhost" >> /etc/apache2/apache2.conf && \
    apache2ctl configtest

COPY config/settings.yml $workdir/config/
COPY start.sh liveness.sh $workdir/
RUN chmod +x $workdir/*.sh
RUN chown -R www-data:www-data /var/www
CMD ["./start.sh"]
