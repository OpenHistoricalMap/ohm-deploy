# Setting up [ohm-website](https://github.com/OpenHistoricalMap/ohm-website) for development mode

Requeriments: docker and docker-compose 

### Step 1: Clone [ohm-website](https://github.com/OpenHistoricalMap/ohm-website) and [ohm-deploy](https://github.com/OpenHistoricalMap/ohm-deploy/) repositories in the same level directory.

```sh

git clone https://github.com/OpenHistoricalMap/ohm-website.git
git clone https://github.com/OpenHistoricalMap/ohm-deploy.git

```

### Step 2:

Uncomment the `volumes` section in `web` - `images/docker-compose.yml` 👇

```yaml
web:
  image: osmseed-web:v1
  build:
    context: ./web
    dockerfile: Dockerfile
  ports:
    - '80:80'
  env_file:
    - ./.env.example
  volumes:
    - ./../../ohm-website:/var/www
```

### Step 3: Build and start the containers

Make sure you have the environment variables set. See `ohm-deploy/images/.env.example` for reference.

```sh
cd ohm-deploy/images/
docker-compose build
# Start DB 
docker-compose up -d db
# Start memcached
docker-compose up -d memcached

# Start web in Dev Mode
docker compose run --service-ports web bash

```

You will have PostgreSQL server setting up its initial database then becoming ready for connections.

If you are connected to an existing DB, set the value in env.exampleand avoid starting the local DB

### Step 4: Setup configuration

Once in the web container is running, execute the following CLI to fill in settings:

```sh
#### MOST ENV VARIABLES ARE SET IN DOCKER CONFIG e.g. DB, MAILER, ETC.

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

#### Setup env vars for memcached server
sed -i -e 's/#memcache_servers: \[\]/memcache_servers: "'$OPENSTREETMAP_memcache_servers'"/g' $workdir/config/settings.yml

## SET NOMINATIM URL
sed -i -e 's/nominatim.openstreetmap.org/'$NOMINATIM_URL'/g' $workdir/config/settings.yml

## SET OVERPASS URL
sed -i -e 's/overpass-api.de/'$OVERPASS_URL'/g' $workdir/config/settings.yml
sed -i -e 's/overpass-api.de/'$OVERPASS_URL'/g' $workdir/app/views/site/export.html.erb
sed -i -e 's/overpass-api.de/'$OVERPASS_URL'/g' $workdir/app/assets/javascripts/index/export.js

touch $workdir/config/settings.local.yml
cp $workdir/config/example.storage.yml $workdir/config/storage.yml
echo "#secrets
production:
  secret_key_base: $(bundle exec rake secret)" >$workdir/config/secrets.yml 
chmod 600 $workdir/config/database.yml $workdir/config/secrets.yml

```

### Step 5: Comment out OAUTH configuration in local ohm-website

Comment out the following lines in `ohm-website/config/settings.yml`

```yml
# oauth_application: "OAUTH_CLIENT_ID"
# oauth_key: "OAUTH_KEY"
# id_key: "xyz"
```

### Step 6: Running Rails CLI

Still within the container, run these commands to install Rake packages and to test everything.

You will see warnings about pngcrush, jpegtran, and other image format tools; ignore them.

```sh
yarn install --trace
bundle exec rake yarn:install --trace
bundle exec rake i18n:js:export --trace
bundle exec rake assets:precompile
bundle exec rails db:migrate
bundle exec rake jobs:work &
apachectl -k start -DFOREGROUND
```

### Step 7: Create a user and OAUTH Tokens

- Create a user: https://localhost/user/new, if the configuration is correct you will receive an email to confirm your local account

- Create [**OAuth 1 settings**](https://user-images.githubusercontent.com/1152236/200726786-648fa334-9993-46e2-bff1-ae76f279a638.png) and set the value from [`Consumer Key`](https://user-images.githubusercontent.com/1152236/200725897-739a2b7c-03cb-4064-accf-58f21e191d6d.png) into `OPENSTREETMAP_id_key`


- Create [**OAuth 2 applications**](https://user-images.githubusercontent.com/1152236/200727159-cf44055e-98c6-4beb-9285-dab467b3ff90.png) and set the value from [`Client ID`](https://user-images.githubusercontent.com/1152236/200727284-679e070d-dee6-4118-a9f4-2bd72ed527f9.png) into `OAUTH_CLIENT_ID` and `Client Secret` into `OAUTH_KEY`.

Press `ctrl + c` to stop the apache process and then export the values and run the following command lines, it will update the `config/settings.yml` file


```sh
export OPENSTREETMAP_id_key=...
export OAUTH_CLIENT_ID=...
export OAUTH_KEY=...

#### SET UP ID KEY
sed -i -e 's/#id_key: ""/id_key: "'$OPENSTREETMAP_id_key'"/g' $workdir/config/settings.yml
### SET UP OAUTH ID AND KEY
sed -i -e 's/OAUTH_CLIENT_ID/'$OAUTH_CLIENT_ID'/g' $workdir/config/settings.yml
sed -i -e 's/OAUTH_KEY/'$OAUTH_KEY'/g' $workdir/config/settings.yml

apachectl -k start -DFOREGROUND
```

Make sure that the following lines are uncomment in `config/settings.yml` 

```yml
# oauth_application: "OAUTH_CLIENT_ID"
# oauth_key: "OAUTH_KEY"
# id_key: "xyz"
```