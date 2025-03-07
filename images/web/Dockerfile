FROM ghcr.io/openhistoricalmap/cgimap:0.0.1-0.dev.git.2087.h94d548c

# Install Passenger
RUN gem install passenger && passenger-install-apache2-module --auto

# Install svgo required
RUN npm install -g svgo

# Install openstreetmap-website
RUN rm -rf $workdir/html
ENV OPENHISTORICALMAP_WEBSITE_GITSHA=86642857be5c38baa60bbff7a60a88963699618a

RUN git clone https://github.com/OpenHistoricalMap/ohm-website.git $workdir \
    && cd $workdir \
    && git checkout $OPENHISTORICALMAP_WEBSITE_GITSHA
WORKDIR $workdir

# change the echo here with a reason for changing the commithash
RUN echo 'updated ohm-website translations but keeping partner keys improperly deleted by translatewiki'
RUN git fetch && rm -rf .git

# Install Ruby packages
RUN gem install bundler && bundle install

# Configure database.yml
RUN cp $workdir/config/example.database.yml $workdir/config/database.yml
RUN touch $workdir/config/settings.local.yml
RUN cp $workdir/config/example.storage.yml $workdir/config/storage.yml
# Protect sensitive information
RUN chmod 600 $workdir/config/database.yml

RUN yarn install
RUN bundle exec rake yarn:install

# Generate RAILS_MASTER_KEY and SECRET_KEY_BASE during build
RUN rm -f config/credentials.yml.enc
RUN export RAILS_MASTER_KEY=$(openssl rand -hex 16) && \
    export SECRET_KEY_BASE=$(rails secret) && \
    echo $RAILS_MASTER_KEY > config/master.key && \
    if [ ! -f config/credentials.yml.enc ]; then \
        EDITOR="echo" RAILS_MASTER_KEY=$RAILS_MASTER_KEY rails credentials:edit; \
    fi && \
    RAILS_MASTER_KEY=$RAILS_MASTER_KEY rails runner " \
        require 'active_support/encrypted_configuration'; \
        require 'yaml'; \
        creds = ActiveSupport::EncryptedConfiguration.new( \
          config_path: 'config/credentials.yml.enc', \
          key_path: 'config/master.key', \
          env_key: 'RAILS_MASTER_KEY', \
          raise_if_missing_key: true \
        ); \
        credentials = { secret_key_base: '${SECRET_KEY_BASE}' }; \
        creds.write(credentials.to_yaml); \
        puts 'Credentials configured correctly.'"
RUN bundle exec rake i18n:js:export --trace
RUN bundle exec rake assets:precompile

# The rack interface requires a `tmp` directory to use openstreetmap-cgimap
RUN ln -s /tmp /var/www/tmp

# Add Apache configuration file
ADD config/production.conf /etc/apache2/sites-available/production.conf
RUN a2enmod headers setenvif proxy proxy_http proxy_fcgi fcgid rewrite lbmethod_byrequests
RUN a2dissite 000-default
RUN a2ensite production

# Enable the Passenger Apache module and restart Apache
RUN echo "ServerName $(cat /etc/hostname)" >> /etc/apache2/apache2.conf

# Config passenger module
RUN echo "LoadModule passenger_module $(passenger-config --root)/buildout/apache2/mod_passenger.so" > /etc/apache2/mods-available/passenger.load
RUN echo "<IfModule mod_passenger.c>\n\
    PassengerRoot $(passenger-config --root)\n\
    PassengerRuby /usr/local/bin/ruby\n\
</IfModule>" > /etc/apache2/mods-available/passenger.conf
RUN a2enmod passenger

# Check installation
RUN /usr/local/bundle/bin/passenger-config validate-install
RUN /usr/local/bundle/bin/passenger-memory-stats

# Config the virtual host apache2
RUN apache2ctl configtest

# Set Permissions for www-data
RUN chown -R www-data: $workdir

# Clone Map-styles
ENV OPENHISTORICALMAP_MAP_STYLES_GITSHA=7a70bbef491db6928f28256a3a68d3158a6f9710
RUN git clone --branch staging --depth 1 https://github.com/OpenHistoricalMap/map-styles.git $workdir/public/map-styles
RUN cd $workdir/public/map-styles && git fetch --depth 1 origin $OPENHISTORICALMAP_MAP_STYLES_GITSHA && git checkout $OPENHISTORICALMAP_MAP_STYLES_GITSHA
RUN rm -rf $workdir/public/map-styles/.git
COPY update_map_styles.py $workdir/

# Clone leaflet-ohm-timeslider-v2
ENV LEAFLET_OHM_TIMESLIDER_V2=dd0acbdc9432fae6a4d09a17a4848c391e5064f0
RUN git clone https://github.com/OpenHistoricalMap/leaflet-ohm-timeslider-v2.git $workdir/public/leaflet-ohm-timeslider-v2 \
    && cd $workdir/public/leaflet-ohm-timeslider-v2 \
    && git checkout dd0acbdc9432fae6a4d09a17a4848c391e5064f0 \
    && rm -rf .git \
    && chmod 777 -R assets/ \
    && cp decimaldate.* $workdir/app/assets/javascripts/ \
    && cp leaflet-ohm-timeslider.* $workdir/app/assets/javascripts/ \
    && cp leaflet-ohm-timeslider.* $workdir/app/assets/stylesheets/ \
    && cp assets/* $workdir/app/assets/images/

# Add settings
ADD config/settings.yml $workdir/config/

COPY start.sh $workdir/
COPY cgimap.sh $workdir/
COPY liveness.sh $workdir/

CMD $workdir/start.sh
