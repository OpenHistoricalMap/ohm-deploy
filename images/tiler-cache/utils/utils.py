import sys
import logging
import psycopg2
import requests
from psycopg2 import OperationalError
from config import Config


def check_tiler_db_postgres_status():
    """Check if the PostgreSQL database is running."""
    logging.info("Checking PostgreSQL database status...")

    try:
        connection = psycopg2.connect(
            host=Config.POSTGRES_HOST,
            port=Config.POSTGRES_PORT,
            database=Config.POSTGRES_DB,
            user=Config.POSTGRES_USER,
            password=Config.POSTGRES_PASSWORD,
            connect_timeout=5,
        )
        connection.close()
        logging.info("PostgreSQL database is running and reachable.")
        return True
    except OperationalError as e:
        logging.error(f"PostgreSQL database is not reachable: {e}")
        return False


def get_purge_and_seed_commands(script_path="purge_seed_tiles.sh"):
    try:
        with open(script_path, "r") as file:
            commands = file.read()
        return commands
    except FileNotFoundError:
        return "Error: Bash script file not found."


def get_logger(name="default_logger"):
    """
    Returns a configured logger instance.

    Args:
        name (str): Name of the logger (default is "default_logger").

    Returns:
        logging.Logger: Configured logger instance.
    """
    logger = logging.getLogger(name)

    if logger.hasHandlers():
        return logger

    for handler in logging.root.handlers[:]:
        logging.root.removeHandler(handler)

    logging.basicConfig(
        format="%(asctime)s - %(levelname)s - %(message)s",
        level=logging.INFO,
        handlers=[logging.StreamHandler(sys.stdout)],
    )

    return logger

# Cloudflare blocks the default python-requests User-Agent
USER_AGENT = "ohm-tiler-cache/1.0"


def s3_path_to_url(s3_path, region="us-east-1"):
    """
    Convert an S3 path (s3://bucket/key) to a download URL.
    With EXPIRED_TILES_BASE_URL set: s3://bucket/key → {base_url}/key
    Otherwise, path-style S3 URL: s3://bucket/key → https://s3.region.amazonaws.com/bucket/key
    """
    if not s3_path.startswith("s3://"):
        raise ValueError("Invalid S3 path. Must start with s3://")

    bucket, key = s3_path.replace("s3://", "").split("/", 1)
    if Config.EXPIRED_TILES_BASE_URL:
        return f"{Config.EXPIRED_TILES_BASE_URL}/{key}"
    url = f"https://s3.{region}.amazonaws.com/{bucket}/{key}"
    return url


def get_list_expired_tiles(url, chunk_size=1000):
    """Download an imposm expire file and return its unique tiles in chunks."""
    response = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=30)
    response.raise_for_status()

    unique_tiles = sorted(set(response.text.split()))
    logging.info(f"Number of unique expired tiles: {len(unique_tiles)}")
    return [unique_tiles[i : i + chunk_size] for i in range(0, len(unique_tiles), chunk_size)]
