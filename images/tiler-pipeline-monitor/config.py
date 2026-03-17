import os


class Config:
    # PostgreSQL (tiler DB)
    POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
    POSTGRES_PORT = int(os.getenv("POSTGRES_PORT", 5432))
    POSTGRES_DB = os.getenv("POSTGRES_DB", "tiler")
    POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
    POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "")

    # Replication
    REPLICATION_STATE_URL = os.getenv(
        "REPLICATION_STATE_URL",
        "https://s3.amazonaws.com/planet.openhistoricalmap.org/replication/minute/state.txt",
    )
    OHM_API_BASE = os.getenv("OHM_API_BASE", "https://www.openhistoricalmap.org/api/0.6")

    # How often to run the pipeline check (seconds)
    CHECK_INTERVAL = int(os.getenv("CHECK_INTERVAL", 3600))  # 1 hour

    # OHM changeset age window (seconds)
    # Only check changesets closed at least CHANGESET_MIN_AGE ago
    # and at most CHANGESET_MAX_AGE ago.
    # Example: min=3600 max=10800 → changesets closed between 1 and 3 hours ago
    CHANGESET_MIN_AGE = int(os.getenv("CHANGESET_MIN_AGE", 10800))    # 1 hour
    CHANGESET_MAX_AGE = int(os.getenv("CHANGESET_MAX_AGE", 14400))   # 3 hours

    # Max number of changesets to check per run
    CHANGESET_LIMIT = int(os.getenv("CHANGESET_LIMIT", 30))

    # Verbose logging
    VERBOSE_LOGGING = os.getenv("VERBOSE_LOGGING", "false").lower() == "true"

    # Alerting (optional)
    SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL", "")

    # Server
    MONITOR_PORT = int(os.getenv("MONITOR_PORT", 8001))

    # S3 tile cache verification
    S3_BUCKET_CACHE_TILER = os.getenv("S3_BUCKET_CACHE_TILER", "")
    S3_BUCKET_PATH_FILES = os.getenv("S3_BUCKET_PATH_FILES", "mnt/data/ohm,mnt/data/ohm_admin,mnt/data/ohm_other_boundaries").split(",")
    TILER_CACHE_AWS_ACCESS_KEY_ID = os.getenv("TILER_CACHE_AWS_ACCESS_KEY_ID", "")
    TILER_CACHE_AWS_SECRET_ACCESS_KEY = os.getenv("TILER_CACHE_AWS_SECRET_ACCESS_KEY", "")
    TILER_CACHE_AWS_ENDPOINT = os.getenv("TILER_CACHE_AWS_ENDPOINT", "https://s3.amazonaws.com")
    TILER_CACHE_REGION = os.getenv("TILER_CACHE_REGION", "us-east-1")
    TILER_CACHE_CLOUD_INFRASTRUCTURE = os.getenv("TILER_CACHE_CLOUD_INFRASTRUCTURE", "aws")
    # Zoom level to verify tile cache (use high zoom for precise check)
    TILE_CHECK_ZOOM = int(os.getenv("TILE_CHECK_ZOOM", 16))
    # Number of random elements to do full pipeline check (tables + views + S3)
    FULL_CHECK_SAMPLE_SIZE = int(os.getenv("FULL_CHECK_SAMPLE_SIZE", 2))

    @staticmethod
    def get_s3_client():
        import boto3
        if Config.TILER_CACHE_CLOUD_INFRASTRUCTURE == "hetzner":
            return boto3.client(
                "s3",
                aws_access_key_id=Config.TILER_CACHE_AWS_ACCESS_KEY_ID,
                aws_secret_access_key=Config.TILER_CACHE_AWS_SECRET_ACCESS_KEY,
                endpoint_url=Config.TILER_CACHE_AWS_ENDPOINT,
                region_name=Config.TILER_CACHE_REGION,
            )
        return boto3.client("s3")

    @staticmethod
    def get_db_dsn():
        return (
            f"postgresql://{Config.POSTGRES_USER}:{Config.POSTGRES_PASSWORD}"
            f"@{Config.POSTGRES_HOST}:{Config.POSTGRES_PORT}/{Config.POSTGRES_DB}"
        )
