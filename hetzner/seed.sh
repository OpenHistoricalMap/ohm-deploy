#!/bin/bash

seed_global() {
  while true; do
    echo "Starting global seeding..."
    pkill -f "tegola" && sleep 5

    # Seed all areas (min 0 to max 5)
    tegola cache seed tile-name "0/0/0"  \
      --config=/opt/tegola_config/config.toml \
      --map=osm \
      --min-zoom=0 \
      --max-zoom=5 \
      --concurrency=32 \
      --overwrite=true

    # Seed land areas separately (zoom 6-7)
    for zoom in $(seq 6 7); do
      echo "Downloading tile list for zoom level $zoom..."
      wget -O /opt/tile-list.tiles "https://s3.amazonaws.com/planet.openhistoricalmap.org/tile_coverage/tiles_boundary_$zoom.list"

      tegola cache seed tile-list /opt/tile-list.tiles \
        --config=/opt/tegola_config/config.toml \
        --map=osm \
        --min-zoom="$zoom" \
        --max-zoom="$zoom" \
        --concurrency=32 \
        --overwrite=true
    done
    echo "Global seeding completed. Sleeping for 1 hour..."
    sleep 3600
  done
}

seed_coverage() {
  while true; do
    echo "Starting coverage seeding..."
    wget -O /opt/tile-list.tiles "https://s3.amazonaws.com/planet.openhistoricalmap.org/tile_coverage/tiles_14.list"
    pkill -f "tegola" && sleep 5

    tegola cache seed tile-list /opt/tile-list.tiles \
      --config=/opt/tegola_config/config.toml \
      --map=osm \
      --min-zoom=8 \
      --max-zoom=14 \
      --concurrency=32 \
      --overwrite=false
  done
}

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <global|coverage>"
  exit 1
fi

case "$1" in
  global)
    seed_global
    ;;
  coverage)
    seed_coverage
    ;;
  *)
    echo "Invalid option. Use 'global' or 'coverage'."
    exit 1
    ;;
esac

