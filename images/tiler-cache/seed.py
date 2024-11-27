import os
import logging
from urllib.parse import urlparse
import click
from utils import (
    upload_to_s3,
    seed_tiles,
    save_geojson_boundary,
    check_tiler_db_postgres_status,
    process_geojson_to_feature_tiles,
)

logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)

# Fetch environment variables
GEOJSON_URL = os.getenv("GEOJSON_URL", None)
ZOOM_LEVELS = os.getenv("ZOOM_LEVELS", "6,7")
CONCURRENCY = int(os.getenv("CONCURRENCY", 32))
S3_BUCKET = os.getenv("S3_BUCKET", "osmseed-dev")
OUTPUT_FILE = os.getenv("OUTPUT_FILE", "log_file.csv")

@click.command(short_help="Script to request or seed tiles from a Tiler API.")
def main():
    """
    Main function to process and seed tiles
    """

    if not GEOJSON_URL:
        logging.error("Environment variable GEOJSON_URL is required but not set. Exiting.")
        return

    logging.info("Starting the tile seeding process.")

    # Check PostgreSQL status
    logging.info("Checking PostgreSQL database status...")
    if not check_tiler_db_postgres_status():
        logging.error("PostgreSQL database is not running or unreachable. Exiting.")
        return
    logging.info("PostgreSQL database is running and reachable.")

    # Extract base name from the GeoJSON URL
    parsed_url = urlparse(GEOJSON_URL)
    base_name = os.path.splitext(os.path.basename(parsed_url.path))[0]
    logging.info(f"Base name extracted from GeoJSON URL: {base_name}")

    # Parse zoom levels
    zoom_levels = list(map(int, ZOOM_LEVELS.split(",")))
    min_zoom = min(zoom_levels)
    max_zoom = max(zoom_levels)
    logging.info(f"Zoom levels parsed: Min Zoom: {min_zoom}, Max Zoom: {max_zoom}")

    # Process GeoJSON and compute tiles
    features, tiles = process_geojson_to_feature_tiles(GEOJSON_URL, min_zoom)
    geojson_file = f"{base_name}_tiles.geojson"
    save_geojson_boundary(features, geojson_file)

    # Use base name for skipped tiles and log files
    skipped_tiles_file = f"{base_name}_skipped_tiles.tiles"
    OUTPUT_FILE = f"{base_name}_seeding_log.csv"

    # Seed the tiles
    logging.info("Starting the seeding process...")
    seed_tiles(tiles, CONCURRENCY, min_zoom, max_zoom, OUTPUT_FILE, skipped_tiles_file)
    logging.info("Tile seeding complete.")
    logging.info(f"Skipped tiles saved to: {skipped_tiles_file}")
    logging.info(f"Log of seeding performance saved to: {OUTPUT_FILE}")

    # Upload log files to S3
    upload_to_s3(OUTPUT_FILE, S3_BUCKET, f"tiler/logs/{OUTPUT_FILE}")
    upload_to_s3(skipped_tiles_file, S3_BUCKET, f"tiler/logs/{skipped_tiles_file}")
    upload_to_s3(geojson_file, S3_BUCKET, f"tiler/logs/{geojson_file}")
    logging.info("Log files uploaded to S3.")

if __name__ == "__main__":
    main()