import logging
import requests
from shapely.geometry import shape, Point, mapping, Polygon
from shapely.ops import unary_union
import csv
import os
import subprocess
import json
from smart_open import open as s3_open
import psycopg2
from psycopg2 import OperationalError
from mercantile import tiles, bounds


def check_tiler_db_postgres_status():
    """Check if the PostgreSQL database is running."""
    logging.info("Checking PostgreSQL database status...")
    POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
    POSTGRES_PORT = int(os.getenv("POSTGRES_PORT", 5432))
    POSTGRES_DB = os.getenv("POSTGRES_DB", "postgres")
    POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
    POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "password")
    try:
        connection = psycopg2.connect(
            host=POSTGRES_HOST,
            port=POSTGRES_PORT,
            database=POSTGRES_DB,
            user=POSTGRES_USER,
            password=POSTGRES_PASSWORD,
            connect_timeout=5,
        )
        connection.close()
        logging.info("PostgreSQL database is running and reachable.")
        return True
    except OperationalError as e:
        logging.error(f"PostgreSQL database is not reachable: {e}")
        return False


def process_geojson_to_feature_tiles(geojson_url, min_zoom):
    """
    Processes a GeoJSON from a URL, computes tiles for each feature at the specified zoom level,
    and returns the tiles as GeoJSON features with tile IDs in properties.

    Args:
        geojson_url (str): URL to the GeoJSON file.
        min_zoom (int): Zoom level for which to compute tiles.

    Returns:
        list: A list of GeoJSON features representing the tiles with their geometries and tile IDs.
    """
    try:
        # Fetch GeoJSON
        logging.info(f"Fetching GeoJSON from {geojson_url}...")
        response = requests.get(geojson_url)
        response.raise_for_status()
        geojson_data = response.json()

        tile_features = []  # List to store tile features
        unique_tiles = set()  # To avoid duplicate tiles

        logging.info(f"Computing tiles at zoom level {min_zoom} for each feature...")
        for feature in geojson_data.get("features", []):
            geom = shape(feature["geometry"])
            feature_bounds = geom.bounds

            for tile in tiles(*feature_bounds, min_zoom):
                # Get tile bounds
                tile_bounds = bounds(tile.x, tile.y, tile.z)

                # Generate the tile geometry
                tile_geom = Polygon(
                    [
                        (tile_bounds.west, tile_bounds.south),
                        (tile_bounds.west, tile_bounds.north),
                        (tile_bounds.east, tile_bounds.north),
                        (tile_bounds.east, tile_bounds.south),
                        (tile_bounds.west, tile_bounds.south),
                    ]
                )

                # Check for intersection
                if geom.intersects(tile_geom):
                    # Ensure no duplicate tiles
                    if (tile.z, tile.x, tile.y) not in unique_tiles:
                        unique_tiles.add((tile.z, tile.x, tile.y))

                        # Add tile as GeoJSON feature with properties
                        tile_features.append(
                            {
                                "type": "Feature",
                                "geometry": mapping(tile_geom),
                                "properties": {"tile_id": f"{tile.z}-{tile.x}-{tile.y}"},
                            }
                        )

        logging.info(f"Computed {len(tile_features)} unique tiles at zoom level {min_zoom}.")
        return tile_features, list(unique_tiles)

    except Exception as e:
        logging.error(f"Error processing GeoJSON to tiles: {e}")
        return [], []

def save_geojson_boundary(features, file_path):
    featureCollection = {"type": "FeatureCollection", "features": features}
    with open(file_path, "w", encoding="utf-8") as file:
        json.dump(featureCollection, file, ensure_ascii=False, indent=4)
    logging.info(f"GeoJSON saved successfully to {file_path}.")

def seed_tiles(tiles, concurrency, min_zoom, max_zoom, log_file, skipped_tiles_file):
    """Seeds tiles using Tegola and logs the process."""

    def load_skipped_tiles():
        if os.path.exists(skipped_tiles_file):
            with open(skipped_tiles_file, "r") as file:
                return set(line.strip() for line in file)
        return set()

    def save_skipped_tiles(skipped_tiles):
        with open(skipped_tiles_file, "w") as file:
            for tile in skipped_tiles:
                file.write(f"{tile}\n")

    def append_to_log(tile_path, time_info):
        with open(log_file, "a", newline="") as file:
            writer = csv.writer(file)
            writer.writerow([tile_path, time_info])

    skipped_tiles = load_skipped_tiles()
    failed_tiles = []

    for tile in tiles:
        z, x, y = tile
        tile_string = f"{z}/{x}/{y}"
        if tile_string in skipped_tiles:
            logging.info(f"Skipping previously skipped tile: {tile_string}")
            continue

        tile_string_file = "tile_file.tiles"
        with open(tile_string_file, "w") as file:
            file.write(tile_string)

        try:
            logging.info(f"Seeding tile: {tile_string} with concurrency {concurrency}")
            command = f"""
            tegola cache seed tile-list {tile_string_file} \
                --config=/opt/tegola_config/config.toml \
                --map=osm \
                --min-zoom={min_zoom} \
                --max-zoom={max_zoom} \
                --overwrite=false \
                --concurrency={concurrency}
            """
            process = subprocess.Popen(
                command,
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )

            for line in process.stdout:
                logging.info(f"STDOUT: {line.strip()}")
                if "took" in line:
                    parts = line.strip().split()
                    tile_path = parts[8].strip("()")
                    time_info = parts[-1]
                    append_to_log(tile_path, time_info)

            for line in process.stderr:
                logging.error(f"STDERR: {line.strip()}")

            process.wait()

            if process.returncode != 0:
                logging.error(f"Failed to seed tile: {tile_string}")
                failed_tiles.append(tile_string)
        except Exception as e:
            logging.error(f"Error processing tile {tile_string}: {e}")
            failed_tiles.append(tile_string)
        finally:
            try:
                os.remove(tile_string_file)
            except Exception as cleanup_error:
                logging.warning(f"Failed to remove temporary file: {cleanup_error}")

    save_skipped_tiles(set(failed_tiles))
    logging.info("Seeding process complete.")
    if failed_tiles:
        logging.error(f"Failed tiles: {failed_tiles}")
    return failed_tiles

def upload_to_s3(local_file, s3_bucket, s3_key):
    """Uploads a local file to an S3 bucket."""
    s3_url = f"s3://{s3_bucket}/{s3_key}"
    try:
        logging.info(f"Uploading {local_file} to {s3_url}...")
        with open(local_file, "rb") as local:
            with s3_open(s3_url, "wb") as remote:
                remote.write(local.read())
        logging.info(f"Uploaded {local_file} to {s3_url}.")
    except Exception as e:
        logging.error(f"Error uploading to S3: {e}")

