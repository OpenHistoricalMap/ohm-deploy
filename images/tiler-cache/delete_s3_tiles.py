#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# Script: delete_s3_tiles.py
# Description:
#   This script deletes cached tile files from an S3 bucket, either:
#     1. By a specified bounding box (bbox) or multiple bboxes
#     2. Or, if no bbox is given, by deleting all tiles per zoom prefix
# -----------------------------------------------------------------------------


import argparse
from config import Config
from utils.utils import get_logger
from utils.s3_utils import (
    generate_tile_patterns_bbox,
    get_and_delete_existing_tiles,
)

logger = get_logger()

s3 = Config.get_s3_client()
BUCKET_NAME = Config.S3_BUCKET_CACHE_TILER
ZOOM_LEVELS = Config.ZOOM_LEVELS_TO_DELETE

logger.info(f"Using S3 bucket: {BUCKET_NAME}")
logger.info(f"Using endpoint: {Config.TILER_CACHE_AWS_ENDPOINT}")
logger.info(f"Using region: {Config.TILER_CACHE_REGION}")
logger.info(f"Zoom levels: {ZOOM_LEVELS}")

def delete_objects_with_prefix(prefix):
    """Delete all objects in the S3 bucket with the specified prefix."""
    logger.info(f"Deleting all objects with prefix: {prefix}")
    paginator = s3.get_paginator("list_objects_v2")
    page_iterator = paginator.paginate(Bucket=BUCKET_NAME, Prefix=prefix)

    deleted = 0
    for page in page_iterator:
        objects = page.get("Contents", [])
        if not objects:
            continue
        keys = [{"Key": obj["Key"]} for obj in objects]
        response = s3.delete_objects(Bucket=BUCKET_NAME, Delete={"Objects": keys})
        deleted += len(response.get("Deleted", []))
        logger.info(f"Deleted {len(response.get('Deleted', []))} objects")

    logger.info(f"Total deleted for prefix '{prefix}': {deleted}")


def delete_tiles_in_bbox(bbox_str, zoom_levels, s3_path):
    """
    Uses efficient prefix filtering to delete tiles in S3 within a given bounding box.
    """
    minx, miny, maxx, maxy = map(float, bbox_str.split(","))
    tile_prefixes = generate_tile_patterns_bbox(minx, miny, maxx, maxy, zoom_levels)

    logger.info(f"Extracted {len(tile_prefixes)} tile prefixes to check.")
    total = get_and_delete_existing_tiles(
        bucket_name=Config.S3_BUCKET_CACHE_TILER,
        path_file=s3_path,
        tiles_patterns=tile_prefixes,
        batch_size=1000,
    )
    logger.info(f"Finished deletion. Total tiles deleted: {total}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Delete cached tiles from S3.")
    parser.add_argument("--bboxes", help="Multiple bboxes separated by '|'")
    
    args = parser.parse_args()

    if args.bboxes:
        logger.info("Deleting tiles for specified bboxes.")
        logger.info(f"bbox: {args.bboxes}")
        logger.info(f"tile_prefix: {args.tile_prefix}")

        bboxes_list = args.bboxes.split("|")
        logger.info(f"Deleting tiles for multiple bboxes: {len(bboxes_list)}")
        for bbox_str in bboxes_list:
            bbox_str = bbox_str.strip()
            if bbox_str:
                logger.info(f"Processing bbox: {bbox_str}")
                delete_tiles_in_bbox(
                    bbox_str=bbox_str,
                    zoom_levels=[12],
                    s3_path=args.tile_prefix
                )
    else:
        logger.info("No bbox provided. Deleting all tiles per zoom level.")
        for zoom in ZOOM_LEVELS:
            prefix = f"mnt/data/osm/{zoom}/"
            delete_objects_with_prefix(prefix)
            
