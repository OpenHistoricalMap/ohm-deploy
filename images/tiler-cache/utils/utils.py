import sys
import logging
import requests
import csv
import os
import subprocess
import json
from smart_open import open as s3_open
import psycopg2
from psycopg2 import OperationalError
from mercantile import tiles, bounds
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
