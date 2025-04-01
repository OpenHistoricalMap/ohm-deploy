FROM ruby:3.3.0
ENV DEBIAN_FRONTEND=noninteractive
ENV workdir=/var/www

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

# Install cgimap v2.0.1
ENV cgimap=/tmp/openstreetmap-cgimap
ENV CGIMAP_GITSHA=8ea707e10aeab5698e6859856111816d75354592
RUN git clone -b master https://github.com/zerebubuth/openstreetmap-cgimap.git $cgimap \
    && cd $cgimap \
    && git checkout $CGIMAP_GITSHA \
    && sed -i 's/OpenStreetMap/OpenHistoricalMap/g' include/cgimap/output_formatter.hpp \
    && sed -i 's|http://www.openstreetmap.org/copyright|https://www.openhistoricalmap.org/copyright|g' include/cgimap/output_formatter.hpp \
    && sed -i 's|http://opendatacommons.org/licenses/odbl/1-0/|https://creativecommons.org/public-domain/cc0/|g' include/cgimap/output_formatter.hpp \
    && rm -rf .git \
    && mkdir build \
    && cd build \
    && cmake .. \
    && cmake --build .
    
RUN cp $cgimap/build/openstreetmap-cgimap /usr/local/bin/ && rm -rf $cgimap

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/local_libs.conf && ldconfig
