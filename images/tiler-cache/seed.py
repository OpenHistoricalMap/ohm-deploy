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


@click.command(short_help="Script to request or seed tiles from a Tiler API.")
@click.option(
    "--geojson-url",
    required=True,
    help="URL to the GeoJSON file defining the area of interest.",
)
@click.option(
    "--zoom-levels",
    help="Comma-separated list of zoom levels",
    default="6,7",
)
@click.option(
    "--concurrency",
    help="Number of concurrent processes for seeding",
    default=32,
    type=int,
)
@click.option(
    "--s3-bucket",
    help="S3 bucket to upload the result CSV file",
    default="osmseed-dev",
)
@click.option(
    "--log-file",
    help="CSV file to save the logs results",
    default="log_file.csv",
)
def main(geojson_url, zoom_levels, concurrency, log_file, s3_bucket):
    """
    Main function to process and seed tiles
    """
    logging.info("Starting the tile seeding process.")

    # Check PostgreSQL status
    logging.info("Checking PostgreSQL database status...")
    if not check_tiler_db_postgres_status():
        logging.error("PostgreSQL database is not running or unreachable. Exiting.")
        return
    logging.info("PostgreSQL database is running and reachable.")

    # Extract base name from the GeoJSON URL
    parsed_url = urlparse(geojson_url)
    base_name = os.path.splitext(os.path.basename(parsed_url.path))[0]
    logging.info(f"Base name extracted from GeoJSON URL: {base_name}")

    # Parse zoom levels
    zoom_levels = list(map(int, zoom_levels.split(",")))
    min_zoom = min(zoom_levels)
    max_zoom = max(zoom_levels)
    logging.info(f"Zoom levels parsed: Min Zoom: {min_zoom}, Max Zoom: {max_zoom}")

    features, tiles = process_geojson_to_feature_tiles(geojson_url, min_zoom)
    geojson_file = f"{base_name}_tiles.geojson"
    save_geojson_boundary(features, geojson_file)

    # Use base name for skipped tiles and log files
    skipped_tiles_file = f"{base_name}_skipped_tiles.tiles"
    log_file = f"{base_name}_seeding_log.csv"

    # Seed the tiles
    logging.info("Starting the seeding process...")
    seed_tiles(tiles, concurrency, min_zoom, max_zoom, log_file, skipped_tiles_file)
    logging.info("Tile seeding complete.")
    logging.info(f"Skipped tiles saved to: {skipped_tiles_file}")
    logging.info(f"Log of seeding performance saved to: {log_file}")

    # Upload log files to S3
    upload_to_s3(log_file, s3_bucket, f"tiler/logs/{log_file}")
    upload_to_s3(skipped_tiles_file, s3_bucket, f"tiler/logs/{skipped_tiles_file}")
    upload_to_s3(skipped_tiles_file, s3_bucket, f"tiler/logs/{geojson_file}")
    logging.info("Log files uploaded to S3.")


if __name__ == "__main__":
    main()
