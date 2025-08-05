#!/bin/bash
set -e

WORKDIR=/data
OSMX_DB_PATH=$WORKDIR/db/osmx.db
PLANET_FILE_PATH=$WORKDIR/planet.osm.pbf

echo $OSMX_DB_PATH
echo $PLANET_FILE_PATH

# mkdir -p "$WORKDIR" $(dirname "$OSMX_DB_PATH")

# # --- 1. Create database if it doesn't exist ---
# if [ ! -d "$OSMX_DB_PATH" ]; then
#     echo "--- Database not found. Initializing..."

#     if [ ! -f "$PLANET_FILE_PATH" ] && [ -n "$PLANET_PBF_URL" ]; then
#         echo "Downloading planet file from $PLANET_PBF_URL..."
#         wget -O "$PLANET_FILE_PATH" "$PLANET_PBF_URL"
#     fi

#     echo "Creating database from planet file..."
#     osmx expand $PLANET_FILE_PATH $OSMX_DB_PATH
#     echo "--- Database created successfully."
# fi


# REPLICATION_INFO=$(osmx query "$OSMX_DB_PATH")

# echo $REPLICATION_INFO

set -ex
export PATH=$PATH:/home/osmx/osmx-adiff-builder

# eval "$(mise activate bash --shims)"

osm replication minute --seqno $(osmx query $1 seqnum) \
  | while read seqno timestamp url; do
  test -z "$seqno" && continue # skip blank lines or empty output

  curl -sL $url | gzip -d > $seqno.osc
  tmpfile=$(mktemp)

  augmented_diff.py $1 $seqno.osc | xmlstarlet format > $tmpfile
  mv $tmpfile $2/$seqno.adiff

  osmx update $1 $seqno.osc $seqno $timestamp --commit
  rm $seqno.osc
done



python utils/osmx-update $OSMX_DB_PATH https://s3.amazonaws.com/planet.openhistoricalmap.org/replication/minute/

# ok esto funciona:

# Entonces vamos a pasar el sequecia num manualemnte o en un env var 1806012
# luego descarga https://s3.amazonaws.com/planet.openhistoricalmap.org/replication/minute/001/806/000.state.txt

# de estaop opten el date y sequece number sequenceNumber y timestamp

# e.g: 
# #Thu Jul 31 15:03:17 UTC 2025
# sequenceNumber=1806000
# txnMaxQueried=7529418
# txnActiveList=
# txnReadyList=
# txnMax=7529418
# timestamp=2025-07-31T15\:01\:13Z


# luego descarga el archivo .osc.gz y lo descomprime

#  wget https://s3.amazonaws.com/planet.openhistoricalmap.org/replication/minute/001/806/012.osc.gz -O 1806012.osc.gz 
#  gunzip -c 1806012.osc.gz > 1806012.osc


# y por ultimo aplica el update

#   osmx update $OSMX_DB_PATH 1806012.osc 1806012 2025-07-31T00:00:00Z --commit

# repote estos pasos 