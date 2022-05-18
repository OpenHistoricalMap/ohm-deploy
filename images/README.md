# Deploy locally docker images for development

Here is simple instruction to test the containers.

- Build and start the containers

```sh
cd images/
docker-compose build
```

- Access to the containers

```sh
docker-compose exec web bash
# root@de6edd6603d7:/var/www#
```

# Setting up [ohm-website](https://github.com/OpenHistoricalMap/ohm-website) for development mode

### Step 1: Clone [ohm-website](https://github.com/OpenHistoricalMap/ohm-website) and [ohm-deploy](https://github.com/OpenHistoricalMap/ohm-deploy/) repositories in the same level

```sh
git clone git@github.com:OpenHistoricalMap/ohm-website.git && cd ohm-website && git checkout merge-osm-website
cd ../
git clone git@github.com:OpenHistoricalMap/ohm-deploy.git && cd ohm-deploy && git checkout new_web_version

```

### Step 2: Open a new terminal tab and and build and start the containers

```sh
# cd ohm-deploy
cd images/
docker-compose up --build
```

### Step 3: Accessing to the container environment

The following code will access to the container en attached the `ohm-website` folder to `/var/www`, so any change in `ohm-website` will reflect in the container

```sh
docker-compose exec web bash
```

Once in the container run the following CLI:

```sh
workdir="/var/www"
export RAILS_ENV=production
#### Because we can not set up many env variable in build process, we are going to process here!

#### SETTING UP THE PRODUCTION DATABASE
echo " # Production DB
production:
  adapter: postgresql
  host: ${POSTGRES_HOST}
  database: ${POSTGRES_DB}
  username: ${POSTGRES_USER}
  password: ${POSTGRES_PASSWORD}
  encoding: utf8" >$workdir/config/database.yml

#### SETTING UP SERVER_URL AND SERVER_PROTOCOL
sed -i -e 's/server_url: "openstreetmap.example.com"/server_url: "'$SERVER_URL'"/g' $workdir/config/settings.yml
sed -i -e 's/server_protocol: "http"/server_protocol: "'$SERVER_PROTOCOL'"/g' $workdir/config/settings.yml

#### SETTING UP MAIL SENDER
sed -i -e 's/smtp_address: "localhost"/smtp_address: "'$MAILER_ADDRESS'"/g' $workdir/config/settings.yml
sed -i -e 's/smtp_domain: "localhost"/smtp_domain: "'$MAILER_DOMAIN'"/g' $workdir/config/settings.yml
sed -i -e 's/smtp_enable_starttls_auto: false/smtp_enable_starttls_auto: true/g' $workdir/config/settings.yml
sed -i -e 's/smtp_authentication: null/smtp_authentication: "login"/g' $workdir/config/settings.yml
sed -i -e 's/smtp_user_name: null/smtp_user_name: "'$MAILER_USERNAME'"/g' $workdir/config/settings.yml
sed -i -e 's/smtp_password: null/smtp_password: "'$MAILER_PASSWORD'"/g' $workdir/config/settings.yml
sed -i -e 's/openstreetmap@example.com/'$MAILER_FROM'/g' $workdir/config/settings.yml
sed -i -e 's/smtp_port: 25/smtp_port: '$MAILER_PORT'/g' $workdir/config/settings.yml

#### SET UP ID KEY
sed -i -e 's/#id_key: ""/id_key: "'$OSM_id_key'"/g' $workdir/config/settings.yml

## SET NOMINATIM URL
sed -i -e 's/nominatim.openstreetmap.org/'$NOMINATIM_URL'/g' $workdir/config/settings.yml

```

### Step 4: Testing Rails CLI

```sh
bundle exec rails db:migrate
bundle exec rake yarn:install
bundle exec rake i18n:js:export
## The following line is falling for assets compilation
bundle exec rake assets:precompile --trace
# bundle exec rake jobs:work
# bundle exec rails test:all
## Start server in port 80
bundle exec rails server -p 80
```
