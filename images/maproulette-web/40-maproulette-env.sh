#!/bin/sh
# Merge runtime VITE_* env vars over the build defaults in env.json,
# e.g. VITE_API_BASE_URL=https://maproulette.openhistoricalmap.org
set -e

env_json=/var/www/maproulette/env.json

jq -n 'env | with_entries(select(.key | startswith("VITE_")))' > /tmp/env.overrides.json
jq -s '.[0] * .[1]' "$env_json" /tmp/env.overrides.json > /tmp/env.json
mv /tmp/env.json "$env_json"

jq -r 'to_entries[] | "env.json: \(.key)=\(.value)"' /tmp/env.overrides.json
