#!/usr/bin/env python3
"""
Watches imposm's expired tile directory and purges corresponding
nginx cache files from Martin's tile cache.

Polls the expire directory for new/modified files, reads tile coordinates,
computes MD5 of nginx cache URIs, and deletes the cache files.

Environment variables:
  EXPIRE_DIR        Path to imposm expire dir (default: /mnt/data/imposm3_expire_dir)
  CACHE_DIR         Nginx cache path (default: /var/cache/nginx/tiles)
  CACHE_LEVELS      Nginx cache levels (default: 1:2)
  NGINX_GROUPS      Comma-separated group names (default: ohm,ohm_admin)
  PURGE_PARENT_ZOOMS  Purge parent tiles up to z0 (default: true)
  POLL_INTERVAL     Seconds between polls (default: 30)
  STATE_FILE        Path to processed files state (default: /app/data/processed_files.json)
  HEALTH_PORT       Health check port (default: 8080)
  MIN_FILE_AGE      Skip files newer than N seconds (default: 5)
  LOG_LEVEL         Logging level (default: INFO)
"""

import glob
import json
import logging
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

# Import purge functions from sibling module
sys.path.insert(0, os.path.dirname(__file__))
from purge_cache import load_group_functions, purge_tiles, read_expired_files

# Configuration
EXPIRE_DIR = os.environ.get("EXPIRE_DIR", "/mnt/data/imposm3_expire_dir")
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "30"))
STATE_FILE = os.environ.get("STATE_FILE", "/app/data/processed_files.json")
HEALTH_PORT = int(os.environ.get("HEALTH_PORT", "8080"))
MIN_FILE_AGE = int(os.environ.get("MIN_FILE_AGE", "5"))
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

# Health state
last_run_time = None
last_run_lock = threading.Lock()
total_files_processed = 0
total_tiles_purged = 0

logger = logging.getLogger("tiler-cache-martin")


def setup_logging():
    level = getattr(logging, LOG_LEVEL.upper(), logging.INFO)
    logging.basicConfig(
        format="%(asctime)s - %(levelname)s - %(message)s",
        level=level,
        handlers=[logging.StreamHandler(sys.stdout)],
    )


def load_state():
    """Load processed files state from disk."""
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE) as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            logger.warning("Corrupted state file, starting fresh")
    return {}


def save_state(state):
    """Persist processed files state to disk."""
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)


def find_new_expire_files(expire_dir, state):
    """Find expire files that are new or modified since last processing."""
    now = time.time()
    new_files = []
    for fpath in sorted(glob.glob(os.path.join(expire_dir, "**", "*"), recursive=True)):
        if not os.path.isfile(fpath):
            continue
        mtime = os.path.getmtime(fpath)
        # Skip files still being written
        if (now - mtime) < MIN_FILE_AGE:
            continue
        recorded_mtime = state.get(fpath)
        if recorded_mtime is None or mtime > recorded_mtime:
            new_files.append((fpath, mtime))
    return new_files


def update_health(files_count, tiles_count):
    """Update health check state."""
    global last_run_time, total_files_processed, total_tiles_purged
    with last_run_lock:
        last_run_time = time.time()
        total_files_processed += files_count
        total_tiles_purged += tiles_count


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            with last_run_lock:
                status = {
                    "status": "healthy",
                    "last_purge_run": last_run_time,
                    "seconds_since_last_run": (
                        round(time.time() - last_run_time, 1) if last_run_time else None
                    ),
                    "total_files_processed": total_files_processed,
                    "total_tiles_purged": total_tiles_purged,
                    "expire_dir": EXPIRE_DIR,
                    "poll_interval": POLL_INTERVAL,
                }
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(status).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # Suppress default request logging


def start_health_server():
    server = HTTPServer(("0.0.0.0", HEALTH_PORT), HealthHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    logger.info(f"Health endpoint on port {HEALTH_PORT}")


def main_loop():
    state = load_state()
    groups = load_group_functions()

    if not groups or all(len(fns) == 0 for fns in groups.values()):
        logger.warning("No groups/functions loaded from functions.json")

    logger.info(
        f"Groups: {', '.join(f'{k} ({len(v)} functions)' for k, v in groups.items())}"
    )

    while True:
        try:
            if not os.path.isdir(EXPIRE_DIR):
                logger.debug(f"Expire dir not found: {EXPIRE_DIR}")
                time.sleep(POLL_INTERVAL)
                continue

            new_files = find_new_expire_files(EXPIRE_DIR, state)

            if new_files:
                logger.info(f"Found {len(new_files)} new/modified expire files")
                cycle_deleted = 0

                for fpath, mtime in new_files:
                    tiles = read_expired_files(fpath)
                    if tiles:
                        deleted, not_found, total_tiles = purge_tiles(tiles, groups)
                        cycle_deleted += deleted
                        logger.info(
                            f"  {os.path.basename(fpath)}: "
                            f"{len(tiles)} expired, "
                            f"{total_tiles} total (with parents), "
                            f"{deleted} deleted, "
                            f"{not_found} not cached"
                        )
                    state[fpath] = mtime

                # Prune state for files that no longer exist
                state = {k: v for k, v in state.items() if os.path.exists(k)}
                save_state(state)
                update_health(len(new_files), cycle_deleted)
                logger.info(f"Cycle done: {cycle_deleted} cache files deleted")

        except Exception as e:
            logger.error(f"Error in main loop: {e}", exc_info=True)

        time.sleep(POLL_INTERVAL)


def main():
    setup_logging()
    logger.info("=== tiler-cache-martin starting ===")
    logger.info(f"  EXPIRE_DIR={EXPIRE_DIR}")
    logger.info(f"  CACHE_DIR={os.environ.get('CACHE_DIR', '/var/cache/nginx/tiles')}")
    logger.info(f"  POLL_INTERVAL={POLL_INTERVAL}s")
    logger.info(f"  MIN_FILE_AGE={MIN_FILE_AGE}s")

    start_health_server()
    main_loop()


if __name__ == "__main__":
    main()
