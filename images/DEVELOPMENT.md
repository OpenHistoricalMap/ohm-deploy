# Setting up [ohm-website](https://github.com/OpenHistoricalMap/ohm-website) for development mode

### Step 1: Clone [ohm-website](https://github.com/OpenHistoricalMap/ohm-website) and [ohm-deploy](https://github.com/OpenHistoricalMap/ohm-deploy/) repositories in the same level

```sh

git clone https://github.com/OpenHistoricalMap/ohm-website.git && cd ohm-website && git checkout merge-osm-website
cd ../
git clone https://github.com/OpenHistoricalMap/ohm-deploy.git && cd ohm-deploy && git checkout new_web_version
cd ../
```

### Step 2:

Replace the `web` section in the file `web.yml` with the following configuration:

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

### Step 3:

Edit `ohm-deploy/images/web/Dockerfile` and replace the CMD line as following:

```
# CMD sh $workdir/start.sh
CMD ["tail", "-f", "/dev/null"]
```

### Step 4: Open a new terminal tab and build and start the containers

```sh
cd ohm-deploy/images/
docker compose -f web.yml up --build
```

This will show the PostgreSQL server setting up its initial database then becoming ready for connections.

### Step 5: Creating config files in the container environment

Run the following CLI under `ohm-deploy/images/` where the `docker-compose.yml` is found.

The following code will connect to the "web" container which attaches the `../../ohm-website` folder to `/var/www`, so any change in `ohm-website` will be reflected in the container's `/var/www` and vice versa.

```sh
docker-compose exec web bash
```

Once in the container run the following CLI to fill in settings:

```sh
#### MOST ENV VARIABLES ARE SET IN DOCKER CONFIG e.g. DB, MAILER, ETC.

export workdir="/var/www"
export RAILS_ENV=production

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

#### SET NOMINATIM URL
sed -i -e "s@https://nominatim.openstreetmap.org/@$NOMINATIM_URL@g" $workdir/config/settings.yml

#### CREATE A BLANK LOCAL SETTINGS FILE
touch $workdir/config/settings.local.yml

### STORAGE CONFIG
cp $workdir/config/example.storage.yml $workdir/config/storage.yml
```

### Step 6: Running Rails CLI

Still within the container, run these commands to install Rake packages and to test everything.

You will see warnings about pngcrush, jpegtran, and other image format tools; ignore them.

```sh
bundle exec rails db:migrate

bundle exec rake yarn:install
yarnpkg --ignore-engines install

bundle exec rake i18n:js:export

## asset compilation fails the first time; run yarnpkg after it fails, then try again
bundle exec rake assets:precompile --trace
yarnpkg --ignore-engines install
bundle exec rake assets:precompile --trace

# bundle exec rake jobs:work
# bundle exec rails test:all
```

### Step 7: Start the web server

Still within the container:

```
## Start server in port 80
bundle exec rails server -p 80
```