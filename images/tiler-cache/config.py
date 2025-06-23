import os
import boto3


class Config:
    # General settings SQS
    ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
    SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "default-queue-url")
    ## In case the container is running in hetzner cloud, we need to load the AWS credentials env vars to read sqs messages
    AWS_REGION_NAME = os.getenv("AWS_REGION_NAME", "us-east-1")

    # Kubernetes settings
    NAMESPACE = os.getenv("NAMESPACE", "default")
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
    ZOOM_LEVELS_TO_DELETE = list(
        map(int, os.getenv("ZOOM_LEVELS_TO_DELETE", "18,19,20").split(","))
    )
    S3_BUCKET_CACHE_TILER = os.getenv("S3_BUCKET_CACHE_TILER", "tiler-cache-staging")
    S3_BUCKET_PATH_FILES = os.getenv("S3_BUCKET_PATH_FILES", "mnt/data/osm")

    # AWS S3 Credentials
    TILER_CACHE_CLOUD_INFRASTRUCTURE = os.getenv(
        "TILER_CACHE_CLOUD_INFRASTRUCTURE", "aws"
    )  # aws or hetzner
    TILER_CACHE_AWS_ACCESS_KEY_ID = os.getenv("TILER_CACHE_AWS_ACCESS_KEY_ID", "")
    TILER_CACHE_AWS_SECRET_ACCESS_KEY = os.getenv("TILER_CACHE_AWS_SECRET_ACCESS_KEY", "")
    TILER_CACHE_AWS_ENDPOINT = os.getenv(
        "TILER_CACHE_AWS_ENDPOINT", "https://s3.amazonaws.com"
    )  # https://s3.amazonaws.com or https://hel1.your-objectstorage.com
    TILER_CACHE_REGION = os.getenv("TILER_CACHE_REGION", "us-east-1")  # us-east-1 or hel1
    TILER_CACHE_BUCKET = os.getenv("TILER_CACHE_BUCKET", "none") 
    # PostgreSQL Database Settings
    POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
    POSTGRES_PORT = int(os.getenv("POSTGRES_PORT", 5432))
    POSTGRES_DB = os.getenv("POSTGRES_DB", "postgres")
    POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
    POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "password")

    DELAYED_CLEANUP_TIMER_SECONDS = int(os.getenv("DELAYED_CLEANUP_TIMER_SECONDS", 3600))

    @staticmethod
    def get_s3_client():
        """Returns an initialized S3 client based on the configured cloud infrastructure."""
        if Config.TILER_CACHE_CLOUD_INFRASTRUCTURE == "aws":
            return boto3.client("s3")
        elif Config.TILER_CACHE_CLOUD_INFRASTRUCTURE == "hetzner":
            return boto3.client(
                "s3",
                aws_access_key_id=Config.TILER_CACHE_AWS_ACCESS_KEY_ID,
                aws_secret_access_key=Config.TILER_CACHE_AWS_SECRET_ACCESS_KEY,
                endpoint_url=Config.TILER_CACHE_AWS_ENDPOINT,
                region_name=Config.TILER_CACHE_REGION,
            )
