#!/bin/bash
set -e

function log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

export PG_CONNECTION="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB"
