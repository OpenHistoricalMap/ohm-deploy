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

    @staticmethod
    def get_db_dsn():
        return (
            f"postgresql://{Config.POSTGRES_USER}:{Config.POSTGRES_PASSWORD}"
            f"@{Config.POSTGRES_HOST}:{Config.POSTGRES_PORT}/{Config.POSTGRES_DB}"
        )
