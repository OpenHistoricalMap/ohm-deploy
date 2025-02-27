import boto3
import re
import logging
from config import Config
from utils.utils import get_logger
from botocore.exceptions import ClientError

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


def generate_all_related_tiles(tiles, zoom_levels):
    """
    Generates a unique sorted list of parent and child tiles for given zoom levels.

    Args:
        tiles (list): List of tiles in "zoom/x/y" format.
        zoom_levels (int | list): Target zoom level(s) to compute parents and children.

    Returns:
        list: A sorted list of all related tiles (parents + children).
    """
    if isinstance(zoom_levels, int):
        zoom_levels = [zoom_levels]
    elif not zoom_levels:
        logger.warning("zoom_levels is empty, returning no tiles.")
        return []

    zoom_levels = sorted(set(zoom_levels))

    related_tiles = set()

    for tile in tiles:
        match = re.match(r"(\d+)/(\d+)/(\d+)", tile)
        if not match:
            logger.warning(f"Skipping invalid tile format: {tile}")
            continue

        z, x, y = map(int, match.groups())

        # Generate parent tiles up to the lowest zoom level
        for parent_zoom in range(z - 1, min(zoom_levels) - 1, -1):
            x //= 2
            y //= 2
            related_tiles.add(f"{parent_zoom}/{x}/{y}")

        # Add the original tile
        related_tiles.add(tile)

        # Generate child tiles down to the highest zoom level
        for child_zoom in range(z + 1, max(zoom_levels) + 1):
            x *= 2
            y *= 2
            related_tiles.update(
                [
                    f"{child_zoom}/{x}/{y}",
                    f"{child_zoom}/{x+1}/{y}",
                    f"{child_zoom}/{x}/{y+1}",
                    f"{child_zoom}/{x+1}/{y+1}",
                ]
            )

    sorted_tiles = sorted(related_tiles)
    logger.info(f"Number related tiles : {len(sorted_tiles)}")

    return sorted_tiles


def generate_tile_patterns(tiles):
    """
    Generate unique tile patterns (zoom/x_prefix) by dynamically removing digits from `x`.

    Rules:
    - 1-2 digits (0-99) → Keep original
    - 3 digits (100-999) → Remove last 1
    - 4+ digits (1000+) → Remove last 2
    """
    patterns = set()

    for tile in tiles:
        match = re.match(r"(\d+)/(\d+)/(\d+)", tile)
        if match:
            zoom, x, _ = match.groups()
            x_str = str(x)
            if len(x_str) <= 2:
                prefix = f"{zoom}/{x_str}"
            elif len(x_str) == 3:
                prefix = f"{zoom}/{x_str[:-1]}"
            else:
                prefix = f"{zoom}/{x_str[:-2]}"
            patterns.add(prefix)
    sorted_patterns = sorted(patterns)
    logger.info(f"tiles patterns: {sorted_patterns}")
    return sorted_patterns


def get_and_delete_existing_tiles(bucket_name, path_file, tiles_patterns, batch_size=1000):
    """
    Efficiently check which tile objects exist in S3 and delete them immediately to prevent accumulation.

    Args:
        bucket_name (str): The name of the S3 bucket.
        path_file (str): The base S3 path.
        tiles_patterns (list): A list of tile patterns in "zoom/x_prefix" format.
        batch_size (int): Number of tile prefixes to check per request.

    Returns:
        int: Total number of deleted tiles.
    """
    s3_client = Config.get_s3_client()
    total_deleted = 0

    tile_prefixes = set()

    # Ensure patterns are in the correct "zoom/x_prefix" format
    for tile in tiles_patterns:
        match = re.match(r"(\d+)/(\d+)", tile)
        if match:
            zoom, x_prefix = match.groups()
            prefix = f"{path_file}/{zoom}/{x_prefix}"
            tile_prefixes.add(prefix)

    try:
        for prefix in tile_prefixes:
            # logger.info(f"Checking and deleting tiles under prefix: {prefix}*")
            paginator = s3_client.get_paginator("list_objects_v2")
            response_iterator = paginator.paginate(Bucket=bucket_name, Prefix=prefix)

            objects_to_delete = []

            for page in response_iterator:
                for obj in page.get("Contents", []):
                    obj_key = obj["Key"]

                    # Add key to deletion batch
                    objects_to_delete.append({"Key": obj_key})

                    # If batch size is reached, delete and reset list
                    if len(objects_to_delete) >= batch_size:
                        s3_client.delete_objects(
                            Bucket=bucket_name, Delete={"Objects": objects_to_delete}
                        )
                        total_deleted += len(objects_to_delete)
                        logger.info(f"Deleted {len(objects_to_delete)} tiles under {prefix}")
                        objects_to_delete = []

            # Delete remaining objects
            if objects_to_delete:
                s3_client.delete_objects(Bucket=bucket_name, Delete={"Objects": objects_to_delete})
                total_deleted += len(objects_to_delete)
                logger.info(f"Deleted {len(objects_to_delete)} tiles under {prefix}")

    except ClientError as e:
        logger.error(f"S3 ClientError while fetching or deleting tiles: {e}")
        raise
    except Exception as e:
        logger.error(f"Error while fetching or deleting tiles from S3: {e}")
        raise

    logger.info(f"Total deleted tiles: {total_deleted}")
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
