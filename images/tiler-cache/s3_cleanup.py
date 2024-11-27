import boto3
import re
import click
import logging

def compute_children_tiles(s3_path, zoom_levels):
    """
    Compute child tiles for the specified zoom levels from a parent tile file in S3.

    Args:
        s3_path (str): S3 path pointing to the .tiles file.
        zoom_levels (list): List of zoom levels for which to compute children.

    Returns:
        list: A list of child tile paths in "zoom/x/y" format only for the target zoom levels.
    """
    logging.info(f"Starting computation of child tiles for {s3_path} and zoom levels {zoom_levels}.")
    
    s3_client = boto3.client("s3")
    s3_match = re.match(r"s3://([^/]+)/(.+)", s3_path)
    if not s3_match:
        raise ValueError(f"Invalid S3 path: {s3_path}")
    
    bucket_name, key = s3_match.groups()
    child_tiles = set()

    try:
        logging.info(f"Fetching file from S3 bucket: {bucket_name}, key: {key}.")
        response = s3_client.get_object(Bucket=bucket_name, Key=key)
        file_content = response["Body"].read().decode("utf-8")
        
        logging.info(f"Processing tiles in file.")
        for line in file_content.splitlines():
            tile = line.strip()
            match = re.match(r"(\d+)/(\d+)/(\d+)", tile)
            if match:
                z, x, y = map(int, match.groups())
                for target_zoom in zoom_levels:
                    while z < target_zoom:
                        x *= 2
                        y *= 2
                        z += 1
                        # Add all 4 children tiles only for the target zoom level
                        if z == target_zoom:
                            child_tiles.add(f"{z}/{x}/{y}")
                            child_tiles.add(f"{z}/{x+1}/{y}")
                            child_tiles.add(f"{z}/{x}/{y+1}")
                            child_tiles.add(f"{z}/{x+1}/{y+1}")

    except Exception as e:
        logging.error(f"Error processing S3 file: {e}")
        raise

    return list(child_tiles)

def generate_tile_patterns(tiles):
    """
    Generate unique tile patterns (zoom/prefix).

    Args:
        tiles (list): List of tile strings in the format 'zoom/x/y'.

    Returns:
        list: List of unique patterns in the format 'zoom/prefix'.
    """
    patterns = set()
    for tile in tiles:
        match = re.match(r"(\d+)/(\d+)/(\d+)", tile)
        if match:
            zoom, x, _ = match.groups()
            prefix = f"{zoom}/{str(x)[:2]}"
            patterns.add(prefix)
    return list(patterns)

def delete_folders_by_pattern(bucket_name, patterns, path_file):
    """
    Delete folders in the S3 bucket matching the pattern:
    s3://<bucket>/mnt/data/osm/<zoom>/<prefix>

    Args:
        bucket_name (str): The name of the S3 bucket.
        patterns (list): A list of patterns in the format '<zoom>/<prefix>'.

    Returns:
        None
    """
    s3_client = boto3.client("s3")

    try:
        for pattern in patterns:
            zoom, prefix = pattern.split("/")
            folder_prefix = f"{path_file}/{zoom}/{prefix}"
            logging.info(f"Looking for objects under folder: {folder_prefix}")
            paginator = s3_client.get_paginator("list_objects_v2")
            response_iterator = paginator.paginate(Bucket=bucket_name, Prefix=folder_prefix)

            for page in response_iterator:
                for obj in page.get("Contents", []):
                    key = obj["Key"]
                    logging.info(f"Deleting object: {key}")
                    s3_client.delete_object(Bucket=bucket_name, Key=key)
        logging.info("Deletion completed for all matching patterns.")
    except Exception as e:
        logging.error(f"Error deleting folders: {e}")
        raise
