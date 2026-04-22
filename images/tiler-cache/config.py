import os


class Config:
    # General settings SQS
    ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
    SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "default-queue-url")
    AWS_REGION_NAME = os.getenv("AWS_REGION_NAME", "us-east-1")

    # Zoom levels to invalidate in Varnish
    ZOOM_LEVELS_TO_DELETE = list(
        map(int, os.getenv("ZOOM_LEVELS_TO_DELETE", "10,11,12,13,14,15,16,17,18,19,20").split(","))
    )

    # PostgreSQL Database Settings
    POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
    POSTGRES_PORT = int(os.getenv("POSTGRES_PORT", 5432))
    POSTGRES_DB = os.getenv("POSTGRES_DB", "postgres")
    POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
    POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "password")

    # Delayed cleanup toggle (scheduled BAN retries via SQS)
    ENABLE_DELAYED_CLEANUP = os.getenv("ENABLE_DELAYED_CLEANUP", "true").lower() == "true"
