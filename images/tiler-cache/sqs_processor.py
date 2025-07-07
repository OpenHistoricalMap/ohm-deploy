import boto3
import time
import os
import json
import threading
import datetime

from tiler_cache_cleaner.cleaner import clean_cache_by_file
from utils.kubernetes_jobs import get_active_k8s_jobs_count, create_kubernetes_job
from config import Config
from utils.utils import (check_tiler_db_postgres_status, get_logger, s3_path_to_url)

logger = get_logger()

# Initialize SQS Client
sqs = boto3.client("sqs", region_name=Config.AWS_REGION_NAME)


def get_active_jobs_count():
    """Returns the number of active jobs based on the infrastructure (Kubernetes or Docker)."""
    if Config.TILER_CACHE_CLOUD_INFRASTRUCTURE == "aws":
        return get_active_k8s_jobs_count(Config.NAMESPACE, Config.JOB_NAME_PREFIX)
    elif Config.TILER_CACHE_CLOUD_INFRASTRUCTURE == "hetzner":
        return 0
    return 0

def cleanup_zoom_levels(s3_imposm3_exp_path, zoom_levels, bucket_name, path_file, cleanup_type="immediate"):
    """Executes the S3 cleanup process for specific zoom levels with improved logging and error handling."""
    logger.info(f"[{cleanup_type.upper()} CLEANUP] Starting...")
    logger.info(f"[{cleanup_type.upper()} CLEANUP] S3 Expiration File: {s3_imposm3_exp_path}")
    logger.info(f"[{cleanup_type.upper()} CLEANUP] Zoom Levels: {sorted(set(zoom_levels))}")
    logger.info(f"[{cleanup_type.upper()} CLEANUP] S3 Bucket: {bucket_name}")
    logger.info(f"[{cleanup_type.upper()} CLEANUP] Target Path: {path_file}")
    try:
        expired_file_url = s3_path_to_url(s3_imposm3_exp_path)
        clean_cache_by_file(expired_file_url, path_file, zoom_levels)
    except Exception as e:
        logger.exception(f"[{cleanup_type.upper()} CLEANUP] Error during S3 cleanup:")
        raise

def process_sqs_messages():
    """Unified function to process SQS messages and create jobs based on infrastructure."""
    while True:
        logger.info("Requesting SQS messages...")
        response = sqs.receive_message(
            QueueUrl=Config.SQS_QUEUE_URL,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=10,
            AttributeNames=["All"],
            MessageAttributeNames=["All"],
        )

        messages = response.get("Messages", [])
        if not messages:
            logger.info("No messages in the queue. Retrying in 5 seconds...")
            time.sleep(5)
            continue

        for message in messages:
            sent_timestamp_ms = int(message["Attributes"]["SentTimestamp"])
            sent_time = datetime.datetime.utcfromtimestamp(sent_timestamp_ms / 1000)
            logger.info(f"{'==' * 40}")
            logger.info(f"Processing message ID {message['MessageId']} created at {sent_time.strftime('%Y-%m-%d %H:%M:%S')} UTC")
            try:
                # Check PostgreSQL status
                if not check_tiler_db_postgres_status():
                    logger.error("PostgreSQL database is down. Exiting.")
                    exit(1)
                    
                # Wait until job limit is under threshold
                while get_active_jobs_count() >= Config.MAX_ACTIVE_JOBS:
                    logger.warning(
                        f"Max active jobs limit ({Config.MAX_ACTIVE_JOBS}) reached. Waiting 1 minute..."
                    )
                    time.sleep(60)

                # Parse the SQS message
                body = json.loads(message["Body"])

                if body.get("action") == "delayed_cleanup":
                    logger.info(f"======== Delay message ID {message['MessageId']}")
                    now = datetime.datetime.utcnow()
                    elapsed_seconds = (now - sent_time).total_seconds()

                    # Only process messages older than the configured delay
                    if elapsed_seconds < Config.DELAYED_CLEANUP_TIMER_SECONDS:
                        logger.info(f"Message was sent {int(elapsed_seconds)} seconds ago. Skipping for now.")
                        continue

                    # Proceed with cleanup
                    s3_imposm3_exp_path = body["s3_path"]
                    cleanup_zoom_levels(
                        s3_imposm3_exp_path=s3_imposm3_exp_path,
                        zoom_levels=Config.ZOOM_LEVELS_TO_DELETE,
                        bucket_name=Config.S3_BUCKET_CACHE_TILER,
                        path_file=Config.S3_BUCKET_PATH_FILES,
                        cleanup_type="delayed"
                    )
                    logger.info("Delayed cleanup executed after 1 hour.")
                    
                if "Records" in body and body["Records"][0]["eventSource"] == "aws:s3":
                    record = body["Records"][0]
                    eventTime = record["eventTime"]
                    bucket_name = record["s3"]["bucket"]["name"]
                    object_key = record["s3"]["object"]["key"]
                    s3_imposm3_exp_path = f"s3://{bucket_name}/{object_key}"
                    file_name = os.path.basename(object_key)
                    # Create a job based on infrastructure
                    if Config.TILER_CACHE_CLOUD_INFRASTRUCTURE == "aws":
                        create_kubernetes_job(s3_imposm3_exp_path, file_name)
                    elif Config.TILER_CACHE_CLOUD_INFRASTRUCTURE == "hetzner":
                        logger.info("Cleaning up in Hetzner")

                        # Immediate cleanup
                        threading.Thread(
                            target=cleanup_zoom_levels,
                            args=(
                                s3_imposm3_exp_path,
                                Config.ZOOM_LEVELS_TO_DELETE,
                                Config.S3_BUCKET_CACHE_TILER,
                                Config.S3_BUCKET_PATH_FILES,
                                "immediate",
                            ),
                        ).start()

                        # Send delayed cleanup via SQS with 1 hour delay
                        sqs.send_message(
                            QueueUrl=Config.SQS_QUEUE_URL,
                            MessageBody=json.dumps({
                                "action": "delayed_cleanup",
                                "s3_path": s3_imposm3_exp_path
                            }),
                            DelaySeconds=900 # Maximun value is 15 min in SQS
                        )

                # Delete the processed message
                sqs.delete_message(
                    QueueUrl=Config.SQS_QUEUE_URL,
                    ReceiptHandle=message["ReceiptHandle"],
                )
                logger.info(f"Message processed and deleted: {message['MessageId']}")

            except Exception as e:
                logger.error(f"Error processing message: {e}")

        time.sleep(10)


if __name__ == "__main__":
    logger.info("Starting SQS message processing")
    process_sqs_messages()
