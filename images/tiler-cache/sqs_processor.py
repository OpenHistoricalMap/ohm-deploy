import boto3
import time
import os
import json
import threading
import datetime

from tiler_cache_cleaner.cleaner import clean_cache_by_file
from config import Config
from utils.utils import (check_tiler_db_postgres_status, get_logger, s3_path_to_url)

logger = get_logger()

# Initialize SQS Client
sqs = boto3.client("sqs", region_name=Config.AWS_REGION_NAME)

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
    """
    Check PostgreSQL database status with retry logic.
    
    Args:
        max_retries (int): Maximum number of retry attempts (default: 3)
        retry_delay (int): Delay in seconds between retries (default: 5)
    
    Returns:
        bool: True if PostgreSQL is available, False otherwise
    """
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


def cleanup_zoom_levels(s3_imposm3_exp_path, zoom_levels, bucket_name, path_file, cleanup_type="immediate"):
    """Executes the S3 cleanup process for specific zoom levels."""
    file_name = os.path.basename(s3_imposm3_exp_path)
    logger.info(f"[{cleanup_type.upper()}] {file_name} | path={path_file} | zooms={min(zoom_levels)}-{max(zoom_levels)}")
    try:
        expired_file_url = s3_path_to_url(s3_imposm3_exp_path)
        clean_cache_by_file(expired_file_url, path_file, zoom_levels)
    except Exception as e:
        logger.exception(f"[{cleanup_type.upper()}] Error: {file_name}")
        raise


def execute_cleanup_for_all_paths(s3_imposm3_exp_path, cleanup_type):
    """
    Executes cleanup for all configured S3 bucket paths in separate threads.

    Args:
        s3_imposm3_exp_path (str): S3 path to the imposm3 expiration file
        cleanup_type (str): Type of cleanup (e.g., "immediate", "delayed_15min", "delayed_1hour")
    """
    for path_file in Config.S3_BUCKET_PATH_FILES:
        threading.Thread(
            target=cleanup_zoom_levels,
            args=(
                s3_imposm3_exp_path,
                Config.ZOOM_LEVELS_TO_DELETE,
                Config.S3_BUCKET_CACHE_TILER,
                path_file,
                cleanup_type,
            ),
        ).start()


# SQS max delay is 15 minutes (900 seconds)
SQS_MAX_DELAY_SECONDS = 900

# Delayed cleanup configurations: (action_name, delay_seconds)
# To add a new delay, just add a tuple here
DELAYED_CLEANUPS = [
    ("delayed_cleanup_15min", 900),   # 15 minutes
    ("delayed_cleanup_1hour", 7200),  # 2 hour
]


def process_delayed_cleanup(body, sent_time, action_name, required_delay_seconds):
    """
    Process a delayed cleanup message if enough time has elapsed.

    Args:
        body (dict): Parsed message body
        sent_time (datetime): When the message was originally sent
        action_name (str): The action name (e.g., "delayed_cleanup_15min")
        required_delay_seconds (int): Required delay before processing

    Returns:
        bool: True if cleanup was executed, False if skipped (not enough time elapsed)
    """
    now = datetime.datetime.utcnow()

    # Use timestamp from message body if available, otherwise use sent_time
    message_timestamp = body.get("timestamp")
    if message_timestamp:
        message_time = datetime.datetime.utcfromtimestamp(message_timestamp)
        elapsed_seconds = (now - message_time).total_seconds()
    else:
        elapsed_seconds = (now - sent_time).total_seconds()

    if elapsed_seconds < required_delay_seconds:
        logger.info(f"[{action_name}] Skipping: {int(elapsed_seconds)}s/{required_delay_seconds}s elapsed")
        return False

    s3_imposm3_exp_path = body["s3_path"]
    cleanup_type = action_name.replace("delayed_cleanup_", "delayed_")
    execute_cleanup_for_all_paths(s3_imposm3_exp_path, cleanup_type)
    return True


def schedule_delayed_cleanups(s3_imposm3_exp_path):
    """
    Schedule all delayed cleanup messages.

    Args:
        s3_imposm3_exp_path (str): S3 path to the imposm3 expiration file
    """
    current_timestamp = int(datetime.datetime.utcnow().timestamp())

    for action_name, delay_seconds in DELAYED_CLEANUPS:
        message_body = {
            "action": action_name,
            "s3_path": s3_imposm3_exp_path,
            "timestamp": current_timestamp
        }

        sqs.send_message(
            QueueUrl=Config.SQS_QUEUE_URL,
            MessageBody=json.dumps(message_body),
            DelaySeconds=min(delay_seconds, SQS_MAX_DELAY_SECONDS)
        )

    scheduled_names = [name for name, _ in DELAYED_CLEANUPS]
    logger.info(f"[SCHEDULED] {os.path.basename(s3_imposm3_exp_path)} -> {', '.join(scheduled_names)}")


def process_sqs_messages():
    """Unified function to process SQS messages and create jobs based on infrastructure."""
    # Initialize heartbeat file
    update_heartbeat()
    
    while True:
        # Update heartbeat at the start of each iteration
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
                    # Terminate the process so the container can be restarted
                    # This will stop the heartbeat updates, causing the health check to fail
                    os._exit(1)

                # Parse the SQS message
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

                # Skip deleting message if it's not ready yet
                if should_skip_delete:
                    continue

                if not is_delayed_message and "Records" in body and body["Records"][0]["eventSource"] == "aws:s3":
                    record = body["Records"][0]
                    eventTime = record["eventTime"]
                    bucket_name = record["s3"]["bucket"]["name"]
                    object_key = record["s3"]["object"]["key"]
                    s3_imposm3_exp_path = f"s3://{bucket_name}/{object_key}"
                    file_name = os.path.basename(object_key)

                    # Immediate cleanup
                    now = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
                    logger.info(f"[S3 FILE] {s3_imposm3_exp_path} | created:{eventTime} | cleaning:{now} UTC")
                    execute_cleanup_for_all_paths(s3_imposm3_exp_path, "immediate")

                    # Send delayed cleanup messages if enabled
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


if __name__ == "__main__":
    logger.info("Starting SQS message processing")
    process_sqs_messages()
