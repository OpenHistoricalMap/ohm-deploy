import os
import boto3

class Config:
    # General settings
    ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
    NAMESPACE = os.getenv("NAMESPACE", "default")
    SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "default-queue-url")
    REGION_NAME = os.getenv("REGION_NAME", "us-east-1")
    CLOUD_INFRASTRUCTURE = os.getenv("CLOUD_INFRASTRUCTURE", "aws")

    # Docker & Kubernetes settings
    DOCKER_IMAGE = os.getenv("DOCKER_IMAGE", "none")
    NODEGROUP_TYPE = os.getenv("NODEGROUP_TYPE", "job_large")
    MAX_ACTIVE_JOBS = int(os.getenv("MAX_ACTIVE_JOBS", 2))
    DELETE_OLD_JOBS_AGE = int(os.getenv("DELETE_OLD_JOBS_AGE", 3600))

    # Tiler cache purge and seed settings
    EXECUTE_PURGE = os.getenv("EXECUTE_PURGE", "true")
    EXECUTE_SEED = os.getenv("EXECUTE_SEED", "true")

    # Zoom levels
    PURGE_MIN_ZOOM = int(os.getenv("PURGE_MIN_ZOOM", 8))
    PURGE_MAX_ZOOM = int(os.getenv("PURGE_MAX_ZOOM", 20))
    SEED_MIN_ZOOM = int(os.getenv("SEED_MIN_ZOOM", 8))
    SEED_MAX_ZOOM = int(os.getenv("SEED_MAX_ZOOM", 14))

    # Concurrency settings
    SEED_CONCURRENCY = int(os.getenv("SEED_CONCURRENCY", 16))
    PURGE_CONCURRENCY = int(os.getenv("PURGE_CONCURRENCY", 16))

    # Job settings
    JOB_NAME_PREFIX = f"{ENVIRONMENT}-tiler-cache-purge"

    # S3 settings
    ZOOM_LEVELS_TO_DELETE = list(map(int, os.getenv("ZOOM_LEVELS_TO_DELETE", "18,19,20").split(",")))
    S3_BUCKET_CACHE_TILER = os.getenv("S3_BUCKET_CACHE_TILER", "tiler-cache-staging")
    S3_BUCKET_PATH_FILES = os.getenv("S3_BUCKET_PATH_FILES", "mnt/data/osm")

    # AWS S3 Credentials
    TILER_CACHE_AWS_ACCESS_KEY_ID = os.getenv("TILER_CACHE_AWS_ACCESS_KEY_ID", "")
    TILER_CACHE_AWS_SECRET_ACCESS_KEY = os.getenv("TILER_CACHE_AWS_SECRET_ACCESS_KEY", "")
    TILER_CACHE_AWS_ENDPOINT = os.getenv("TILER_CACHE_AWS_ENDPOINT", "https://s3.amazonaws.com")
    TILER_CACHE_REGION = os.getenv("TILER_CACHE_REGION", "us-east-1")

    @staticmethod
    def get_s3_client():
        """Returns an initialized S3 client based on the configured cloud infrastructure."""
        if Config.CLOUD_INFRASTRUCTURE == "aws":
            return boto3.client("s3")
        elif Config.CLOUD_INFRASTRUCTURE == "hetzner":
            return boto3.client(
                "s3",
                aws_access_key_id=Config.TILER_CACHE_AWS_ACCESS_KEY_ID,
                aws_secret_access_key=Config.TILER_CACHE_AWS_SECRET_ACCESS_KEY,
                endpoint_url=Config.TILER_CACHE_AWS_ENDPOINT,
                region_name=Config.TILER_CACHE_REGION,
            )