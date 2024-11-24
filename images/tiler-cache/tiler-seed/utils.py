import logging
import requests
import mercantile
from shapely.geometry import shape, Point, mapping
from shapely.ops import unary_union
import csv
import os
import subprocess
import json
from smart_open import open as s3_open


def read_geojson_boundary(geojson_url, feature_type, buffer_distance_km=0.01):
    """Fetches and processes GeoJSON boundary data."""
    try:
        logging.info(f"Fetching GeoJSON from {geojson_url}...")
        response = requests.get(geojson_url)
        response.raise_for_status()
        geojson_data = response.json()
        geometries = [shape(feature["geometry"]) for feature in geojson_data["features"]]

        if not geometries:
            logging.warning("No geometry found in GeoJSON.")
            return None

        if feature_type == "Polygon":
            return unary_union(geometries)
        elif feature_type == "Point":
            buffered_geometries = [
                geom.buffer(buffer_distance_km) for geom in geometries if isinstance(geom, Point)
            ]
            return unary_union(buffered_geometries) if buffered_geometries else None
        else:
            raise ValueError(f"Unsupported feature type: {feature_type}.")
    except Exception as e:
        logging.error(f"Error reading GeoJSON boundary: {e}")
        return None


def save_geojson_boundary(boundary_geometry, file_path):
    """Saves the GeoJSON boundary to a file."""
    if not boundary_geometry:
        logging.warning("No geometry to save.")
        return

    try:
        geojson_data = {
            "type": "FeatureCollection",
            "features": [
                {"type": "Feature", "geometry": mapping(boundary_geometry), "properties": {}}
            ],
        }

        with open(file_path, "w", encoding="utf-8") as file:
            json.dump(geojson_data, file, ensure_ascii=False, indent=4)
        logging.info(f"GeoJSON saved successfully to {file_path}.")
    except Exception as e:
        logging.error(f"Error saving GeoJSON file: {e}")


def boundary_to_tiles(boundary_geometry, min_zoom, max_zoom):
    """Generates a list of tiles from boundary geometry."""
    if not boundary_geometry:
        logging.warning("No valid geometry provided.")
        return []

    logging.info(f"Generating tiles for zoom levels {min_zoom} to {max_zoom}...")
    tile_list = []
    minx, miny, maxx, maxy = boundary_geometry.bounds
    for z in range(min_zoom, max_zoom + 1):
        for tile in mercantile.tiles(minx, miny, maxx, maxy, z):
            tile_geom = shape(mercantile.feature(tile)["geometry"])
            if boundary_geometry.intersects(tile_geom):
                tile_list.append(f"{z}/{tile.x}/{tile.y}")
    logging.info(f"Generated {len(tile_list)} tiles.")
    return tile_list


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

    for tile_string in tiles:
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
