import boto3
import re
from config import Config
from utils.utils import get_logger
from botocore.exceptions import ClientError
import mercantile
import time 

logger = get_logger()

def get_list_expired_tiles(s3_imposm3_exp_path):
    """
    Fetches a list of expired tiles from an S3 file.

    Args:
        s3_imposm3_exp_path (str): S3 path pointing to the expired tiles file.

    Returns:
        list: A list of expired tile paths.
    """
    s3_client = boto3.client("s3")

    # Validate S3 path format
    s3_match = re.match(r"s3://([^/]+)/(.+)", s3_imposm3_exp_path)
    if not s3_match:
        raise ValueError(f"Invalid S3 path format: {s3_imposm3_exp_path}")

    bucket_name, key = s3_match.groups()

    try:
        response = s3_client.get_object(Bucket=bucket_name, Key=key)
        file_content = response["Body"].read().decode("utf-8").strip()

        if not file_content:
            logger.warning("The file is empty. No expired tiles found.")
            return []

        tiles = file_content.splitlines()
        logger.info(f"Number Expired tiles: {len(tiles)}")
        return tiles

    except ClientError as e:
        logger.error(f"S3 ClientError: {e}")
        raise
    except Exception as e:
        logger.error(f"Error processing S3 file: {e}")
        raise

def generate_tile_patterns_from_related(tiles, zoom_levels):
    """
    Generate zoom/x_prefix patterns from parent and child tiles efficiently.
    """
    if isinstance(zoom_levels, int):
        zoom_levels = [zoom_levels]
    elif not zoom_levels:
        logger.warning("zoom_levels is empty, returning no patterns.")
        return []

    zoom_levels = sorted(set(zoom_levels))
    patterns = set()

    def add_pattern(z, x):
        x_str = str(x)
        if len(x_str) <= 2:
            prefix = f"{z}/{x_str}"
        elif len(x_str) == 3:
            prefix = f"{z}/{x_str[:-1]}"
        else:
            prefix = f"{z}/{x_str[:-2]}"
        patterns.add(prefix)

    for tile in tiles:
        match = re.match(r"(\d+)/(\d+)/(\d+)", tile)
        if not match:
            logger.warning(f"Skipping invalid tile format: {tile}")
            continue

        z, x, y = map(int, match.groups())
        add_pattern(z, x)

        # Parents
        px, py = x, y
        for parent_zoom in range(z - 1, min(zoom_levels) - 1, -1):
            px //= 2
            py //= 2
            add_pattern(parent_zoom, px)

        # Children
        for child_zoom in range(z + 1, max(zoom_levels) + 1):
            factor = 2 ** (child_zoom - z)
            for dx in range(factor):
                add_pattern(child_zoom, x * factor + dx)

    sorted_patterns = sorted(patterns)
    logger.info(f"Generated {len(sorted_patterns)} tile patterns from {len(tiles)} input tiles.")
    return sorted_patterns



def generate_tile_patterns_bbox(minx, miny, maxx, maxy, zoom_levels):
    """
    Generate minimal set of unique tile prefixes z/x_prefix based on tile.x only.
    Avoids iterating over full tile list (x/y) to save time.
    """
    prefixes = set()

    for z in zoom_levels:
        # Only store unique x prefixes at this zoom level
        x_prefix_set = set()
        tiles = mercantile.tiles(minx, miny, maxx, maxy, [z])

        for tile in tiles:
            x_str = str(tile.x)
            if len(x_str) <= 2:
                x_prefix = x_str
            elif len(x_str) == 3:
                x_prefix = x_str[:-1]
            else:
                x_prefix = x_str[:-2]

            x_prefix_set.add(f"{z}/{x_prefix}")

        prefixes.update(x_prefix_set)
        logger.info(f"Zoom {z}: {len(x_prefix_set)} unique x_prefixes")

    logger.info(f"Total unique prefixes: {len(prefixes)}")
    return sorted(prefixes)

def get_and_delete_existing_tiles(bucket_name, path_file, tiles_patterns, batch_size=1000, color="\033[0m"):
    """
    Efficiently check which tile objects exist in S3 and delete them immediately to prevent accumulation.
    """
    s3_client = Config.get_s3_client()
    total_deleted = 0
    total_found = 0
    tile_prefixes = set()
    # Prepare tile prefixes
    for tile in tiles_patterns:
        match = re.match(r"(\d+)/(\d+)", tile)
        if match:
            zoom, x_prefix = match.groups()
            prefix = f"{path_file}/{zoom}/{x_prefix}"
            tile_prefixes.add(prefix)

    start_time = time.time()
    total_patterns = len(tile_prefixes)
    processed_patterns = 0

    try:
        for prefix in tile_prefixes:

            paginator = s3_client.get_paginator("list_objects_v2")
            response_iterator = paginator.paginate(Bucket=bucket_name, Prefix=prefix)

            objects_to_delete = []
            found_this_prefix = 0

            for page in response_iterator:
                contents = page.get("Contents", [])
                total_found += len(contents)
                found_this_prefix += len(contents)

                for obj in contents:
                    obj_key = obj["Key"]
                    objects_to_delete.append({"Key": obj_key})

                    if len(objects_to_delete) >= batch_size:
                        s3_client.delete_objects(
                            Bucket=bucket_name,
                            Delete={"Objects": objects_to_delete}
                        )
                        total_deleted += len(objects_to_delete)
                        print(f"{color}[{processed_patterns + 1}/{total_patterns}] Deleted {len(objects_to_delete)} tiles under {prefix}*{color}")
                        objects_to_delete = []

            if objects_to_delete:
                s3_client.delete_objects(
                    Bucket=bucket_name,
                    Delete={"Objects": objects_to_delete}
                )
                total_deleted += len(objects_to_delete)

            processed_patterns += 1
            logger.info(f"{color}[{processed_patterns}/{total_patterns}] Deleted {found_this_prefix} objects under prefix {prefix}{color}")

    except ClientError as e:
        logger.error(f"S3 ClientError while fetching or deleting tiles: {e}")
        raise
    except Exception as e:
        logger.error(f"Error while fetching or deleting tiles from S3: {e}")
        raise

    elapsed_time = time.time() - start_time
    print(f"{color}S3 cleanup completed in {elapsed_time:.2f} seconds{color}")
    print(f"{color}Total tiles found: {total_found}{color}")
    print(f"{color}Total deleted tiles: {total_deleted}{color}")

    return total_deleted

def delete_folders_by_pattern(bucket_name, patterns, path_file, batch_size=1000):
    """
    Delete folders in the S3 bucket matching the pattern:
    s3://<bucket>/mnt/data/osm/<zoom>/<prefix>***, using bulk delete.

    Args:
        bucket_name (str): The name of the S3 bucket.
        patterns (list): A list of patterns in the format '<zoom>/<prefix>...'.
        path_file (str): The base path in S3 where objects are stored.
        batch_size (int): Number of objects to delete per request (default 1000).

    Returns:
        None
    """
    s3_client = Config.get_s3_client()

    try:
        for pattern in patterns:
            zoom, prefix = pattern.split("/")
            folder_prefix = f"{path_file}/{zoom}/{prefix}"
            logger.info(f"Fetching objects under prefix: {folder_prefix}...")

            paginator = s3_client.get_paginator("list_objects_v2")
            response_iterator = paginator.paginate(Bucket=bucket_name, Prefix=folder_prefix)

            objects_to_delete = []
            for page in response_iterator:
                for obj in page.get("Contents", []):
                    obj_key = obj["Key"]
                    logger.info(f"Marked for deletion: {bucket_name}/{obj_key}")
                    objects_to_delete.append({"Key": obj_key})

                    # Delete in batches of `batch_size`
                    if len(objects_to_delete) >= batch_size:
                        logger.info(
                            f"INFRASTRUTURE {Config.CLOUD_INFRASTRUCTURE},  REGION: {Config.AWS_REGION_NAME} , BUCKER Deleting {len(objects_to_delete)} objects under the patern: {patterns}"
                        )
                        s3_client.delete_objects(
                            Bucket=bucket_name, Delete={"Objects": objects_to_delete}
                        )
                        objects_to_delete = []

            # Delete remaining objects if any
            if objects_to_delete:
                logger.info(
                    f"Deleting final {len(objects_to_delete)} objects under the patern: {patterns}...in bucket and region: {bucket_name} {Config.AWS_REGION_NAME}"
                )
                s3_client.delete_objects(Bucket=bucket_name, Delete={"Objects": objects_to_delete})

        logger.info("Bulk deletion completed for all matching patterns.")

    except Exception as e:
        print(f"Error during bulk deletion: {e}")
        logger.error(f"Error during bulk deletion: {e}")
        raise
