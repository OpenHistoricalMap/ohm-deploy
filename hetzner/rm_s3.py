# This script is used to delete cached files from an S3 bucket, typically after a migration or tile modification.
# When using the standard s3 rm --recursive command, deleting a large number of tile files can take hours.
# This script improves the process deleting in batches of 1,000 per request, significantly speeding up the cleanup.

import os
import boto3
from botocore.exceptions import ClientError

BUCKET_NAME = os.getenv("BUCKET_NAME", "tiler-cache-production")
ACCESS_KEY = os.getenv("TILER_CACHE_AWS_ACCESS_KEY_ID")
SECRET_KEY = os.getenv("TILER_CACHE_AWS_SECRET_ACCESS_KEY")
ENDPOINT = os.getenv("TILER_CACHE_AWS_ENDPOINT")
REGION = os.getenv("TILER_CACHE_REGION", "us-east-1")
ZOOM_LEVELS = os.getenv("ZOOM_LEVELS", "0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20").split(
    ","
)

if not ACCESS_KEY or not SECRET_KEY or not ENDPOINT:
    raise Exception(
        "Missing required environment variables: ACCESS_KEY, SECRET_KEY, or ENDPOINT."
    )

s3 = boto3.client(
    "s3",
    aws_access_key_id=ACCESS_KEY,
    aws_secret_access_key=SECRET_KEY,
    endpoint_url=ENDPOINT,
    region_name=REGION,
)


def delete_objects_with_prefix(prefix):
    print(f"Listing objects with prefix: {prefix}")
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
        print(f"Deleted {len(response.get('Deleted', []))} objects")

    print(f"Total deleted for {prefix}: {deleted}")


for zoom in ZOOM_LEVELS:
    prefix = f"mnt/data/osm/{zoom.strip()}/"
    delete_objects_with_prefix(prefix)
