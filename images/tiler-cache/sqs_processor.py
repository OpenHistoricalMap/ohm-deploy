import boto3
import time
import os
import json
import threading
import datetime
import glob as glob_module

from config import Config
from utils.utils import (check_tiler_db_postgres_status, get_logger, s3_path_to_url)

logger = get_logger()

# Heartbeat file path for health checks
HEARTBEAT_FILE = "/tmp/sqs_processor_heartbeat"
HEARTBEAT_TIMEOUT_SECONDS = 60


def update_heartbeat():
    """Update heartbeat file to signal that SQS processor is alive."""
    try:
        with open(HEARTBEAT_FILE, 'w') as f:
            f.write(str(time.time()))
    except Exception as e:
        logger.warning(f"Failed to update heartbeat file: {e}")


def check_postgres_with_retries(max_retries=3, retry_delay=5):
    """Check PostgreSQL database status with retry logic."""
    for attempt in range(max_retries):
        if check_tiler_db_postgres_status():
            return True
        else:
            if attempt < max_retries - 1:
                logger.warning(f"PostgreSQL database is down. Retrying in {retry_delay} seconds... (attempt {attempt + 1}/{max_retries})")
                time.sleep(retry_delay)
            else:
                logger.error("PostgreSQL database is down after all retries.")
    return False


# ─── S3 backend cleanup (Tegola) ───────────────────────────────────────────

def cleanup_zoom_levels_s3(s3_imposm3_exp_path, zoom_levels, bucket_name, path_file, cleanup_type="immediate"):
    """Executes the S3 cleanup process for specific zoom levels."""
    from tiler_cache_cleaner.cleaner import clean_cache_by_file
    file_name = os.path.basename(s3_imposm3_exp_path)
    logger.info(f"[{cleanup_type.upper()}] [S3] {file_name} | path={path_file} | zooms={min(zoom_levels)}-{max(zoom_levels)}")
    try:
        expired_file_url = s3_path_to_url(s3_imposm3_exp_path)
        clean_cache_by_file(expired_file_url, path_file, zoom_levels)
    except Exception as e:
        logger.exception(f"[{cleanup_type.upper()}] [S3] Error: {file_name}")
        raise


def execute_cleanup_s3(s3_imposm3_exp_path, cleanup_type):
    """Executes S3 cleanup for all configured paths in separate threads."""
    for path_file in Config.S3_BUCKET_PATH_FILES:
        threading.Thread(
            target=cleanup_zoom_levels_s3,
            args=(
                s3_imposm3_exp_path,
                Config.ZOOM_LEVELS_TO_DELETE,
                Config.S3_BUCKET_CACHE_TILER,
                path_file,
                cleanup_type,
            ),
        ).start()


# ─── Nginx backend cleanup (Martin) ────────────────────────────────────────

def parse_tile_line(line):
    """Parse a tile line in format z/x/y."""
    line = line.strip()
    if not line or line.startswith("#"):
        return None
    parts = line.split("/")
    if len(parts) != 3:
        return None
    try:
        return int(parts[0]), int(parts[1]), int(parts[2])
    except ValueError:
        return None


def read_expired_tiles_from_s3(s3_path):
    """Read tile coordinates from an S3 expire file.

    Uses the default AWS S3 client (not the tile cache client) because
    expire files are stored in AWS S3 even when tile cache is on Hetzner.
    """
    tiles = set()
    try:
        # Expire files are always in AWS S3 (same account as SQS)
        s3 = boto3.client("s3", region_name=Config.AWS_REGION_NAME)
        # Parse s3://bucket/key
        path = s3_path.replace("s3://", "")
        bucket, key = path.split("/", 1)
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response["Body"].read().decode("utf-8")
        for line in content.splitlines():
            tile = parse_tile_line(line)
            if tile:
                tiles.add(tile)
    except Exception as e:
        logger.error(f"Failed to read expire file from S3: {s3_path}: {e}")
    return tiles


def read_expired_tiles_from_local(path):
    """Read tile coordinates from a local file or directory."""
    tiles = set()
    if os.path.isdir(path):
        for fpath in sorted(glob_module.glob(os.path.join(path, "**", "*"), recursive=True)):
            if os.path.isfile(fpath):
                with open(fpath) as f:
                    for line in f:
                        tile = parse_tile_line(line)
                        if tile:
                            tiles.add(tile)
    elif os.path.isfile(path):
        with open(path) as f:
            for line in f:
                tile = parse_tile_line(line)
                if tile:
                    tiles.add(tile)
    return tiles


def execute_cleanup_nginx(s3_imposm3_exp_path, cleanup_type):
    """
    Read expire file and purge matching tiles from nginx cache volume.

    The expire file can be in S3 (SQS mode) or local (local mode).
    """
    from nginx_purger import purge_tiles_from_nginx

    # Read tiles from S3 expire file
    tiles = read_expired_tiles_from_s3(s3_imposm3_exp_path)
    if not tiles:
        logger.info(f"[{cleanup_type.upper()}] [NGINX] No expired tiles found in {s3_imposm3_exp_path}")
        return

    result = purge_tiles_from_nginx(tiles)
    file_name = os.path.basename(s3_imposm3_exp_path)
    logger.info(
        f"[{cleanup_type.upper()}] [NGINX] {file_name} | "
        f"expired={len(tiles)} | total_with_parents={result['total_tiles']} | "
        f"deleted={result['deleted']} | not_cached={result['not_found']}"
    )


def execute_cleanup_nginx_local(expire_path, cleanup_type):
    """Read local expire files and purge matching tiles from nginx cache volume."""
    from nginx_purger import purge_tiles_from_nginx

    tiles = read_expired_tiles_from_local(expire_path)
    if not tiles:
        return

    result = purge_tiles_from_nginx(tiles)
    logger.info(
        f"[{cleanup_type.upper()}] [NGINX] {expire_path} | "
        f"expired={len(tiles)} | total_with_parents={result['total_tiles']} | "
        f"deleted={result['deleted']} | not_cached={result['not_found']}"
    )


# ─── Unified cleanup dispatcher ────────────────────────────────────────────

def execute_cleanup(s3_imposm3_exp_path, cleanup_type):
    """Dispatch cleanup to the correct backend."""
    if Config.CACHE_BACKEND == "nginx":
        execute_cleanup_nginx(s3_imposm3_exp_path, cleanup_type)
    else:
        execute_cleanup_s3(s3_imposm3_exp_path, cleanup_type)


# ─── Delayed cleanup (SQS) ─────────────────────────────────────────────────

# SQS max delay is 15 minutes (900 seconds)
SQS_MAX_DELAY_SECONDS = 900

# Delayed cleanup configurations: (action_name, delay_seconds)
DELAYED_CLEANUPS = [
    ("delayed_cleanup_15min", 900),   # 15 minutes
    ("delayed_cleanup_1hour", 7200),  # 1 hour
    ("delayed_cleanup_2hour", 14400),  # 2 hour
    ("delayed_cleanup_12hour", 43200),  # 12 hour
    ("delayed_cleanup_24hour", 86400),  # 24 hour
]


def process_delayed_cleanup(body, sent_time, action_name, required_delay_seconds):
    """Process a delayed cleanup message if enough time has elapsed."""
    now = datetime.datetime.utcnow()

    message_timestamp = body.get("timestamp")
    if message_timestamp:
        message_time = datetime.datetime.utcfromtimestamp(message_timestamp)
        elapsed_seconds = (now - message_time).total_seconds()
    else:
        elapsed_seconds = (now - sent_time).total_seconds()

    if elapsed_seconds < required_delay_seconds:
        logger.info(f"[{action_name}] Skipping: {int(elapsed_seconds)}s/{required_delay_seconds}s elapsed")
        return False

    expire_path = body.get("expire_path") or body.get("s3_path")
    cleanup_type = action_name.replace("delayed_cleanup_", "delayed_")
    backend = body.get("cache_backend", Config.CACHE_BACKEND)

    if backend == "nginx" and not expire_path.startswith("s3://"):
        # Local expire file → purge nginx volume
        execute_cleanup_nginx_local(expire_path, cleanup_type)
    else:
        # S3 expire file → dispatch to configured backend
        execute_cleanup(expire_path, cleanup_type)
    return True


def schedule_delayed_cleanups(expire_path):
    """
    Schedule all delayed cleanup messages via SQS.

    Args:
        expire_path: S3 path (s3://bucket/key) or local path (/mnt/data/...)
    """
    sqs = boto3.client("sqs", region_name=Config.AWS_REGION_NAME)
    current_timestamp = int(datetime.datetime.utcnow().timestamp())

    for action_name, delay_seconds in DELAYED_CLEANUPS:
        message_body = {
            "action": action_name,
            "expire_path": expire_path,
            "s3_path": expire_path,  # backwards compat for Tegola messages in flight
            "cache_backend": Config.CACHE_BACKEND,
            "timestamp": current_timestamp
        }

        sqs.send_message(
            QueueUrl=Config.SQS_QUEUE_URL,
            MessageBody=json.dumps(message_body),
            DelaySeconds=min(delay_seconds, SQS_MAX_DELAY_SECONDS)
        )

    scheduled_names = [name for name, _ in DELAYED_CLEANUPS]
    logger.info(f"[SCHEDULED] {os.path.basename(expire_path)} -> {', '.join(scheduled_names)}")


# ─── SQS input mode ────────────────────────────────────────────────────────

def process_sqs_messages():
    """Poll SQS for expire messages and dispatch to the correct backend."""
    sqs = boto3.client("sqs", region_name=Config.AWS_REGION_NAME)
    update_heartbeat()

    while True:
        update_heartbeat()
        logger.debug("Polling SQS...")
        response = sqs.receive_message(
            QueueUrl=Config.SQS_QUEUE_URL,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=10,
            AttributeNames=["All"],
            MessageAttributeNames=["All"],
        )

        messages = response.get("Messages", [])
        if not messages:
            time.sleep(5)
            continue

        for message in messages:
            sent_timestamp_ms = int(message["Attributes"]["SentTimestamp"])
            sent_time = datetime.datetime.utcfromtimestamp(sent_timestamp_ms / 1000)
            msg_id_short = message['MessageId'][:8]
            logger.info("=="*40)
            logger.info(f"============= msg:{msg_id_short} | sent:{sent_time.strftime('%Y-%m-%d %H:%M')} UTC =============")
            try:
                # Check PostgreSQL status with retry logic
                if not check_postgres_with_retries():
                    logger.error("PostgreSQL database is down after all retries. Terminating process to trigger container restart.")
                    os._exit(1)

                body = json.loads(message["Body"])

                # Process delayed cleanup messages
                is_delayed_message = False
                should_skip_delete = False
                for action_name, delay_seconds in DELAYED_CLEANUPS:
                    if body.get("action") == action_name:
                        is_delayed_message = True
                        if not process_delayed_cleanup(body, sent_time, action_name, delay_seconds):
                            should_skip_delete = True
                        break

                if should_skip_delete:
                    continue

                if not is_delayed_message and "Records" in body and body["Records"][0]["eventSource"] == "aws:s3":
                    record = body["Records"][0]
                    eventTime = record["eventTime"]
                    bucket_name = record["s3"]["bucket"]["name"]
                    object_key = record["s3"]["object"]["key"]
                    s3_imposm3_exp_path = f"s3://{bucket_name}/{object_key}"

                    now = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
                    logger.info(f"[S3 FILE] {s3_imposm3_exp_path} | created:{eventTime} | cleaning:{now} UTC")
                    execute_cleanup(s3_imposm3_exp_path, "immediate")

                    if Config.ENABLE_DELAYED_CLEANUP:
                        schedule_delayed_cleanups(s3_imposm3_exp_path)

                # Delete the processed message
                sqs.delete_message(
                    QueueUrl=Config.SQS_QUEUE_URL,
                    ReceiptHandle=message["ReceiptHandle"],
                )
                logger.info(f"[DONE] msg:{msg_id_short}")

            except Exception as e:
                logger.error(f"Error processing message: {e}")

        time.sleep(10)


# ─── Local input mode (poll expire directory) ──────────────────────────────

STATE_FILE = "/app/data/processed_files.json"


def load_state():
    """Load processed files state."""
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_state(state):
    """Save processed files state."""
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)


def process_local_expire_dir():
    """Poll local imposm expire directory and purge cache."""
    update_heartbeat()
    state = load_state()
    expire_dir = Config.LOCAL_EXPIRE_DIR

    logger.info(f"[LOCAL] Watching {expire_dir} every {Config.LOCAL_POLL_INTERVAL}s (backend={Config.CACHE_BACKEND})")

    while True:
        update_heartbeat()

        if not os.path.isdir(expire_dir):
            time.sleep(Config.LOCAL_POLL_INTERVAL)
            continue

        # Find all expire files
        new_files = []
        for fpath in sorted(glob_module.glob(os.path.join(expire_dir, "**", "*"), recursive=True)):
            if not os.path.isfile(fpath):
                continue
            mtime = os.path.getmtime(fpath)
            age = time.time() - mtime
            if age < Config.LOCAL_MIN_FILE_AGE:
                continue
            prev_mtime = state.get(fpath)
            if prev_mtime is not None and prev_mtime >= mtime:
                continue
            new_files.append((fpath, mtime))

        if new_files:
            logger.info(f"[LOCAL] Found {len(new_files)} new/updated expire files")
            for fpath, mtime in new_files:
                # Immediate purge
                if Config.CACHE_BACKEND == "nginx":
                    execute_cleanup_nginx_local(fpath, "immediate")
                else:
                    execute_cleanup_s3_from_local(fpath, "immediate")

                # Schedule delayed cleanup waves via SQS
                if Config.ENABLE_DELAYED_CLEANUP:
                    schedule_delayed_cleanups(fpath)

                state[fpath] = mtime

            save_state(state)

            # Prune state for deleted files
            state = {k: v for k, v in state.items() if os.path.exists(k)}
            save_state(state)

        time.sleep(Config.LOCAL_POLL_INTERVAL)


def execute_cleanup_s3_from_local(expire_path, cleanup_type):
    """Read local expire file and delete tiles from S3 (local input + S3 backend)."""
    from tiler_cache_cleaner.cleaner import clean_cache_by_file
    tiles = read_expired_tiles_from_local(expire_path)
    if not tiles:
        return
    # Write tiles to a temp file and use the S3 cleaner
    for path_file in Config.S3_BUCKET_PATH_FILES:
        logger.info(f"[{cleanup_type.upper()}] [LOCAL→S3] {expire_path} | {len(tiles)} tiles | path={path_file}")
        try:
            zoom_levels = Config.ZOOM_LEVELS_TO_DELETE
            # Filter tiles to configured zoom levels
            filtered = [(z, x, y) for z, x, y in tiles if z in zoom_levels]
            if filtered:
                s3 = Config.get_s3_client()
                bucket = Config.S3_BUCKET_CACHE_TILER
                keys = [f"{path_file}/{z}/{x}/{y}" for z, x, y in filtered]
                # Batch delete from S3
                for i in range(0, len(keys), 1000):
                    batch = [{"Key": k} for k in keys[i:i+1000]]
                    s3.delete_objects(Bucket=bucket, Delete={"Objects": batch, "Quiet": True})
        except Exception as e:
            logger.exception(f"[{cleanup_type.upper()}] [LOCAL→S3] Error: {expire_path}")


# ─── SQS delayed message listener (runs in background thread) ──────────────

def process_sqs_delayed_messages():
    """
    Listen for delayed cleanup messages from SQS.
    Used alongside local polling to process scheduled waves.
    """
    sqs = boto3.client("sqs", region_name=Config.AWS_REGION_NAME)
    logger.info("[SQS-DELAYED] Listening for delayed cleanup messages...")

    while True:
        try:
            response = sqs.receive_message(
                QueueUrl=Config.SQS_QUEUE_URL,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=10,
                AttributeNames=["All"],
                MessageAttributeNames=["All"],
            )

            messages = response.get("Messages", [])
            if not messages:
                continue

            for message in messages:
                sent_timestamp_ms = int(message["Attributes"]["SentTimestamp"])
                sent_time = datetime.datetime.utcfromtimestamp(sent_timestamp_ms / 1000)
                msg_id_short = message['MessageId'][:8]

                try:
                    body = json.loads(message["Body"])

                    # Only process delayed cleanup messages
                    processed = False
                    should_skip_delete = False
                    for action_name, delay_seconds in DELAYED_CLEANUPS:
                        if body.get("action") == action_name:
                            if not process_delayed_cleanup(body, sent_time, action_name, delay_seconds):
                                should_skip_delete = True
                            processed = True
                            break

                    if should_skip_delete:
                        continue

                    if processed:
                        sqs.delete_message(
                            QueueUrl=Config.SQS_QUEUE_URL,
                            ReceiptHandle=message["ReceiptHandle"],
                        )
                        logger.info(f"[SQS-DELAYED] Done msg:{msg_id_short}")

                except Exception as e:
                    logger.error(f"[SQS-DELAYED] Error processing message: {e}")

        except Exception as e:
            logger.error(f"[SQS-DELAYED] Error receiving messages: {e}")
            time.sleep(10)


# ─── Entry point ────────────────────────────────────────────────────────────

if __name__ == "__main__":
    logger.info(f"Starting cache purge processor (backend={Config.CACHE_BACKEND}, input={Config.INPUT_MODE})")

    if Config.INPUT_MODE == "local":
        # Start SQS delayed listener in background thread (for wave cleanups)
        if Config.ENABLE_DELAYED_CLEANUP:
            sqs_thread = threading.Thread(target=process_sqs_delayed_messages, daemon=True)
            sqs_thread.start()
            logger.info("[LOCAL] SQS delayed listener started in background")

        # Main thread: poll local expire directory
        process_local_expire_dir()
    else:
        process_sqs_messages()
