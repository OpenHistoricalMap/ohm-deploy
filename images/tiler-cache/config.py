import os
import boto3


class Config:
    # ─── General settings ───────────────────────────────────────────────────
    # Environment name: "development", "staging", "production"
    ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
    # SQS queue URL for receiving expire notifications and delayed cleanup waves
    # Example: "https://sqs.us-east-1.amazonaws.com/123456789012/ohm-tiler-cache-production"
    SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "default-queue-url")
    # AWS region for SQS: "us-east-1", "eu-central-1", etc.
    AWS_REGION_NAME = os.getenv("AWS_REGION_NAME", "us-east-1")

    # ─── Cache backend ──────────────────────────────────────────────────────
    # Which cache storage to purge:
    #   "s3"    → Tegola: tiles stored in S3, deleted via S3 API
    #   "nginx" → Martin: tiles stored in nginx proxy_cache volume, deleted via filesystem
    CACHE_BACKEND = os.getenv("CACHE_BACKEND", "s3")

    # ─── Input mode ─────────────────────────────────────────────────────────
    # How to receive expire notifications:
    #   "sqs"   → Poll SQS queue for S3 event notifications (Tegola setup)
    #   "local" → Poll local directory for imposm expire files (Martin setup)
    INPUT_MODE = os.getenv("INPUT_MODE", "sqs")

    # ─── Purge settings ──────────────────────────────────────────────────────
    # Enable/disable purge: "true" or "false"
    EXECUTE_PURGE = os.getenv("EXECUTE_PURGE", "true")
    # Min/max zoom for purge: 0-20
    PURGE_MIN_ZOOM = int(os.getenv("PURGE_MIN_ZOOM", 8))
    PURGE_MAX_ZOOM = int(os.getenv("PURGE_MAX_ZOOM", 20))
    # Parallel threads for purge: 4, 8, 16, 32
    PURGE_CONCURRENCY = int(os.getenv("PURGE_CONCURRENCY", 16))

    # ─── S3 settings (used when CACHE_BACKEND=s3) ──────────────────────────
    # Zoom levels to delete from S3: comma-separated, e.g. "8,9,10,11,12,13,14,15,16,17,18,19,20"
    ZOOM_LEVELS_TO_DELETE = list(
        map(int, os.getenv("ZOOM_LEVELS_TO_DELETE", "10,11,12,13,14,15,16,17,18,19,20").split(","))
    )
    # S3 bucket where Tegola tiles are cached
    # Example: "tiler-cache-production", "tiler-cache-staging"
    S3_BUCKET_CACHE_TILER = os.getenv("S3_BUCKET_CACHE_TILER", "tiler-cache-staging")
    # S3 key prefixes for tile groups, comma-separated
    # Example: "mnt/data/ohm,mnt/data/ohm_admin,mnt/data/ohm_other_boundaries"
    S3_BUCKET_PATH_FILES = os.getenv("S3_BUCKET_PATH_FILES", "mnt/data/ohm,mnt/data/ohm_admin,mnt/data/ohm_other_boundaries").split(",")

    # ─── AWS / S3-compatible credentials ────────────────────────────────────
    # Cloud provider: "aws" (Amazon S3) or "hetzner" (S3-compatible)
    TILER_CACHE_CLOUD_INFRASTRUCTURE = os.getenv("TILER_CACHE_CLOUD_INFRASTRUCTURE", "aws")
    # S3 access key (required for hetzner, optional for aws if using IAM roles)
    # Example: "AKIAIOSFODNN7EXAMPLE"
    TILER_CACHE_AWS_ACCESS_KEY_ID = os.getenv("TILER_CACHE_AWS_ACCESS_KEY_ID", "")
    # S3 secret key
    # Example: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    TILER_CACHE_AWS_SECRET_ACCESS_KEY = os.getenv("TILER_CACHE_AWS_SECRET_ACCESS_KEY", "")
    # S3 endpoint URL:
    #   AWS:     "https://s3.amazonaws.com"
    #   Hetzner: "https://hel1.your-objectstorage.com"
    TILER_CACHE_AWS_ENDPOINT = os.getenv("TILER_CACHE_AWS_ENDPOINT", "https://s3.amazonaws.com")
    # S3 region:
    #   AWS:     "us-east-1", "eu-west-1"
    #   Hetzner: "hel1", "fsn1"
    TILER_CACHE_REGION = os.getenv("TILER_CACHE_REGION", "us-east-1")
    # S3 bucket name for tile storage: "ohm-tiles-production", "ohm-tiles-staging"
    TILER_CACHE_BUCKET = os.getenv("TILER_CACHE_BUCKET", "none")

    # ─── Nginx cache settings (used when CACHE_BACKEND=nginx) ───────────────
    # Path to nginx proxy_cache directory (Docker volume shared with Martin container)
    # Example: "/var/cache/nginx/tiles"
    NGINX_CACHE_DIR = os.getenv("NGINX_CACHE_DIR", "/var/cache/nginx/tiles")
    # Nginx cache levels (must match proxy_cache_path levels in nginx.conf)
    # Example: "1:2" → {cache_dir}/{last1char}/{next2chars}/{md5hash}
    NGINX_CACHE_LEVELS = os.getenv("NGINX_CACHE_LEVELS", "1:2")
    # Tile groups to purge, comma-separated (must match nginx route groups)
    # Example: "ohm,ohm_admin,ohm_other_boundaries"
    NGINX_GROUPS = os.getenv("NGINX_GROUPS", "ohm,ohm_admin,ohm_other_boundaries").split(",")
    # Also purge parent tiles: "true" or "false"
    # When true, purging z14/8192/5461 also purges z13/4096/2730, ..., up to NGINX_PURGE_PARENT_MIN_ZOOM
    NGINX_PURGE_PARENT_ZOOMS = os.getenv("NGINX_PURGE_PARENT_ZOOMS", "true").lower() == "true"
    # Minimum zoom for parent purge (default: 6). Tiles below this expire via proxy_cache_valid.
    NGINX_PURGE_PARENT_MIN_ZOOM = int(os.getenv("NGINX_PURGE_PARENT_MIN_ZOOM", 6))
    # Maximum zoom for child purge (default: 15). Tiles above this expire via proxy_cache_valid.
    NGINX_PURGE_CHILD_MAX_ZOOM = int(os.getenv("NGINX_PURGE_CHILD_MAX_ZOOM", 15))
    # Path to functions.json (defines layer names per group for per-layer URI generation)
    # Example: "/app/config/functions.json"
    NGINX_FUNCTIONS_JSON = os.getenv("NGINX_FUNCTIONS_JSON", "/app/config/functions.json")

    # ─── Local expire dir settings (used when INPUT_MODE=local) ─────────────
    # Directory where imposm writes expire tile files
    # Example: "/mnt/data/imposm3_expire_dir"
    LOCAL_EXPIRE_DIR = os.getenv("LOCAL_EXPIRE_DIR", "/mnt/data/imposm3_expire_dir")
    # How often to poll for new expire files, in seconds: 10, 30, 60
    LOCAL_POLL_INTERVAL = int(os.getenv("LOCAL_POLL_INTERVAL", 30))
    # Minimum file age before processing (avoids reading incomplete files), in seconds: 3, 5, 10
    LOCAL_MIN_FILE_AGE = int(os.getenv("LOCAL_MIN_FILE_AGE", 5))

    # ─── PostgreSQL Database Settings ───────────────────────────────────────
    # Tiler database connection (used for health checks before processing)
    # Example: host="37.27.96.98" or "tiler-db.ohm.internal"
    POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
    # Example: 5432, 54329
    POSTGRES_PORT = int(os.getenv("POSTGRES_PORT", 5432))
    # Example: "tiler_osm", "ohm_tiler"
    POSTGRES_DB = os.getenv("POSTGRES_DB", "postgres")
    # Example: "postgres", "ohm_reader"
    POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
    POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "password")

    # ─── Delayed cleanup (SQS waves) ───────────────────────────────────────
    # Delayed waves re-purge tiles after MVs have refreshed.
    # MVs can take minutes to hours to refresh (REFRESH MATERIALIZED VIEW CONCURRENTLY),
    # so the immediate purge may re-cache stale tiles. Waves ensure eventual consistency.
    #
    # Timer between delayed checks, in seconds: 3600 (1h)
    DELAYED_CLEANUP_TIMER_SECONDS = int(os.getenv("DELAYED_CLEANUP_TIMER_SECONDS", 3600))
    # Enable/disable delayed cleanup waves: "true" or "false"
    # When true, schedules 5 waves via SQS: 15min, 1h, 2h, 12h, 24h
    ENABLE_DELAYED_CLEANUP = os.getenv("ENABLE_DELAYED_CLEANUP", "true").lower() == "true"
    DELAYED_CLEANUP_15MIN_SECONDS = 900  # 15 minutes
    DELAYED_CLEANUP_1HOUR_SECONDS = 3600  # 1 hour

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
