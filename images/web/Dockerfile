FROM ruby:3.3.0
ENV DEBIAN_FRONTEND=noninteractive
ENV workdir /var/www

# Production OSM setup
ENV RAILS_ENV=production

# Install the openstreetmap-website dependencies
RUN apt-get update \
    && apt-get install -y \
    libmagickwand-dev libxml2-dev libxslt1-dev \
    apache2 apache2-dev build-essential git-core postgresql-client \
    libpq-dev libsasl2-dev imagemagick libffi-dev libgd-dev libarchive-dev libbz2-dev curl \
    default-jre-headless file gpg-agent libvips-dev locales software-properties-common tzdata unzip \
    advancecomp gifsicle libjpeg-progs jhead jpegoptim optipng pngcrush pngquant \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install node
RUN curl -sL https://deb.nodesource.com/setup_18.x | bash -
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
RUN apt-get update && apt-get install -y nodejs yarn && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install openstreetmap-cgimap requirements
RUN apt-get update &&  apt-get -y install libxml2-dev libpqxx-dev libfcgi-dev zlib1g-dev libbrotli-dev \
  libboost-program-options-dev libfmt-dev libmemcached-dev libcrypto++-dev \
  libargon2-dev libyajl-dev cmake libapache2-mod-fcgid && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Install cgimap
ENV cgimap /tmp/openstreetmap-cgimap
ENV CGIMAP_GITSHA=e465c3ff9ebb07a9c808d7c821236041d63434b5
RUN git clone -b master https://github.com/zerebubuth/openstreetmap-cgimap.git $cgimap
RUN cd $cgimap && git checkout $CGIMAP_GITSHA
RUN cd $cgimap && \
    mkdir build && \
    cd build && \
    cmake .. && \
    cmake --build .
RUN cp $cgimap/build/openstreetmap-cgimap /usr/local/bin/ && rm -rf $cgimap

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/local_libs.conf && ldconfig

# Install Passenger
RUN gem install passenger && passenger-install-apache2-module --auto

# Install svgo required
RUN npm install -g svgo

# Install openstreetmap-website
RUN rm -rf $workdir/html
ENV OPENHISTORICALMAP_WEBSITE_GITSHA=554ecad1f56a0880f67af3b1255a9ffb39f6d41a
RUN git clone -b staging https://github.com/OpenHistoricalMap/ohm-website.git $workdir
WORKDIR $workdir
RUN git checkout $OPENHISTORICALMAP_WEBSITE_GITSHA

# change the echo here with a reason for changing the commithash
RUN echo 'bring in latest style changes'
RUN git fetch

# Install Ruby packages
RUN gem install bundler && bundle install

# Configure database.yml and secrets.yml
RUN cp $workdir/config/example.database.yml $workdir/config/database.yml
RUN touch $workdir/config/settings.local.yml
RUN cp $workdir/config/example.storage.yml $workdir/config/storage.yml
RUN echo "#session key \n\
production: \n\
  secret_key_base: $(bundle exec rake secret)" > $workdir/config/secrets.yml
# Protect sensitive information
RUN chmod 600 $workdir/config/database.yml $workdir/config/secrets.yml

RUN yarn install
RUN bundle exec rake yarn:install
RUN bundle exec rake i18n:js:export
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
ENV OPENHISTORICALMAP_MAP_STYLES_GITSHA=3a74377fbd1a2e2cb9e74db911643f98c436c080
RUN git clone --branch staging --depth 1 https://github.com/OpenHistoricalMap/map-styles.git $workdir/public/map-styles
RUN cd $workdir/public/map-styles && git fetch --depth 1 origin $OPENHISTORICALMAP_MAP_STYLES_GITSHA && git checkout $OPENHISTORICALMAP_MAP_STYLES_GITSHA
RUN rm -rf $workdir/public/map-styles/.git
COPY update_map_styles.py $workdir/

# Add settings
ADD config/settings.local.yml $workdir/config/

COPY start.sh $workdir/
COPY cgimap.sh $workdir/
COPY liveness.sh $workdir/

CMD $workdir/start.sh