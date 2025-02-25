import boto3
import re
import logging


def compute_children_tiles(s3_path, zoom_levels):
    """
    Compute child tiles for the specified zoom levels from a parent tile file in S3.

    Args:
        s3_path (str): S3 path pointing to the .tiles file.
        zoom_levels (list): List of zoom levels for which to compute children.

    Returns:
        list: A sorted list of unique child tile paths in "zoom/x/y" format only for the target zoom levels.
    """
    logging.info(
        f"Starting computation of child tiles for {s3_path} and zoom levels {sorted(set(zoom_levels))}."
    )

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
                for target_zoom in sorted(set(zoom_levels)):
                    while z < target_zoom:
                        x *= 2
                        y *= 2
                        z += 1
                        if z == target_zoom:
                            child_tiles.update(
                                [
                                    f"{z}/{x}/{y}",
                                    f"{z}/{x+1}/{y}",
                                    f"{z}/{x}/{y+1}",
                                    f"{z}/{x+1}/{y+1}",
                                ]
                            )

    except Exception as e:
        logging.error(f"Error processing S3 file: {e}")
        raise

    return sorted(child_tiles)


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
            x_str = str(x)
            # If x has 2 or more digits, take the first 2 digits; otherwise, keep it as is
            prefix = f"{zoom}/{x_str[:2]}" if len(x_str) > 1 else f"{zoom}/{x_str}"
            patterns.add(prefix)

    return sorted(patterns)


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
    s3_client = boto3.client("s3")

    try:
        for pattern in patterns:
            zoom, prefix = pattern.split("/")
            folder_prefix = f"{path_file}/{zoom}/{prefix}"
            logging.info(f"Fetching objects under prefix: {folder_prefix}...")

            paginator = s3_client.get_paginator("list_objects_v2")
            response_iterator = paginator.paginate(
                Bucket=bucket_name, Prefix=folder_prefix
            )

            objects_to_delete = []
            for page in response_iterator:
                for obj in page.get("Contents", []):
                    obj_key = obj["Key"]
                    # logging.info(f"Marked for deletion: {bucket_name}/{obj_key}")
                    objects_to_delete.append({"Key": obj_key})

                    # Delete in batches of `batch_size`
                    if len(objects_to_delete) >= batch_size:
                        logging.info(f"Deleting {len(objects_to_delete)} objects under the patern: {patterns}...")
                        s3_client.delete_objects(
                            Bucket=bucket_name, Delete={"Objects": objects_to_delete}
                        )
                        objects_to_delete = []

            # Delete remaining objects if any
            if objects_to_delete:
                print(f"Deleting final {len(objects_to_delete)} objects under the patern: {patterns}...")
                logging.info(f"Deleting final {len(objects_to_delete)} objects under the patern: {patterns}...")
                s3_client.delete_objects(
                    Bucket=bucket_name, Delete={"Objects": objects_to_delete}
                )

        print("Bulk deletion completed for all matching patterns.")
        logging.info("Bulk deletion completed for all matching patterns.")

    except Exception as e:
        print(f"Error during bulk deletion: {e}")
        logging.error(f"Error during bulk deletion: {e}")
        raise
