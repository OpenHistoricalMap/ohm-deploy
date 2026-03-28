import os
import re


def _parse_duration(value, default):
    """Parse human-readable duration (e.g. '1h', '30m', '1.5h', '2h30m', '3600') to seconds."""
    raw = os.getenv(value, "")
    if not raw:
        return default
    # If it's just a number, treat as seconds
    try:
        return int(float(raw))
    except ValueError:
        pass
    total = 0
    for amount, unit in re.findall(r"(\d+\.?\d*)\s*(h|m|s)", raw.lower()):
        amount = float(amount)
        if unit == "h":
            total += amount * 3600
        elif unit == "m":
            total += amount * 60
        elif unit == "s":
            total += amount
    return int(total) if total > 0 else default


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

    # How often to run the pipeline check (e.g. "1h", "30m", "3600")
    CHECK_INTERVAL = _parse_duration("TILER_MONITORING_CHECK_INTERVAL", 3600)

    # OHM changeset age window (e.g. "1h", "2h30m", "3600")
    CHANGESET_MIN_AGE = _parse_duration("TILER_MONITORING_CHANGESET_MIN_AGE", 10800)
    CHANGESET_MAX_AGE = _parse_duration("TILER_MONITORING_CHANGESET_MAX_AGE", 14400)

    # Max number of changesets to check per run
    CHANGESET_LIMIT = int(os.getenv("CHANGESET_LIMIT", 30))

    # Retry: how many times to recheck a missing element before alerting
    MAX_RETRIES = int(os.getenv("TILER_MONITORING_MAX_RETRIES", 3))

    # Missing threshold: minimum percentage of missing elements in a changeset
    # to consider it a real failure. Below this threshold, elements are marked
    # as "warning" instead of "failed" and do NOT trigger RSS/Slack alerts.
    # e.g. 10 = 10% — if only 1/44 elements is missing (2.3%), it's a warning.
    MISSING_THRESHOLD_PCT = int(os.getenv("TILER_MONITORING_MISSING_THRESHOLD_PCT", 10))

    # Verbose logging
    VERBOSE_LOGGING = os.getenv("VERBOSE_LOGGING", "false").lower() == "true"

    # Alerting (optional)
    SLACK_WEBHOOK_URL = os.getenv("TILER_MONITORING_SLACK_WEBHOOK_URL", "")

    # Server
    MONITOR_PORT = int(os.getenv("MONITOR_PORT", 8001))
    MONITOR_BASE_URL = os.getenv("TILER_MONITORING_BASE_URL", "")

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
    # Percentage of elements to do full pipeline check (tables + views + S3)
    # e.g. 25 = 25% of elements, minimum 1
    FULL_CHECK_SAMPLE_PCT = int(os.getenv("TILER_MONITORING_FULL_CHECK_SAMPLE_PCT", 25))

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
