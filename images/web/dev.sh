# !/bin/bash

source ./start.sh

workdir="/var/www"
export RAILS_ENV=development

setup_env_vars 

cat <<EOF > "$workdir/config/database.yml"
$RAILS_ENV:
  adapter: postgresql
  host: ${POSTGRES_HOST}
  database: ${POSTGRES_DB}
  username: ${POSTGRES_USER}
  password: ${POSTGRES_PASSWORD}
  encoding: utf8
EOF

cat <<EOF > "$workdir/config/storage.yml"
local:
  service: Disk
  root: <%= Rails.root.join("storage") %>
EOF

cat <<EOF >> "$workdir/config/storage.yml"
s3:
  service: S3
  region: '$RAILS_STORAGE_REGION'
  bucket: '$RAILS_STORAGE_BUCKET'
EOF

gem update bundler
bundle install
bundle exec bin/yarn install
bundle exec rails s -p 3000 -b '0.0.0.0'
