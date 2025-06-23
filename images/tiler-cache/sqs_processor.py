import boto3
import time
import os
import json
import threading

from utils.s3_utils import (
    get_list_expired_tiles,
    generate_all_related_tiles,
    generate_tile_patterns,
    get_and_delete_existing_tiles,
)
from utils.kubernetes_jobs import get_active_k8s_jobs_count, create_kubernetes_job

from utils.utils import check_tiler_db_postgres_status
from config import Config
from utils.utils import get_logger

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
        expired_tiles = get_list_expired_tiles(s3_imposm3_exp_path)
        related_tile = generate_all_related_tiles(expired_tiles, zoom_levels)
        tiles_patterns = generate_tile_patterns(related_tile)
        get_and_delete_existing_tiles(bucket_name, path_file, tiles_patterns)
        logger.info(f"[{cleanup_type.upper()} CLEANUP] S3 Cleanup Completed Successfully.")
    except Exception as e:
        logger.exception(f"[{cleanup_type.upper()} CLEANUP] Error during S3 cleanup:")
        raise

def process_sqs_messages():
    """Unified function to process SQS messages and create jobs based on infrastructure."""
    while True:
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


                # Handle delayed cleanup
                if body.get("action") == "delayed_cleanup":
                    s3_imposm3_exp_path = body["s3_path"]
                    cleanup_zoom_levels(
                        s3_imposm3_exp_path=s3_imposm3_exp_path,
                        zoom_levels=Config.ZOOM_LEVELS_TO_DELETE,
                        bucket_name=Config.S3_BUCKET_CACHE_TILER,
                        path_file=Config.S3_BUCKET_PATH_FILES,
                        cleanup_type="delayed"
                    )
                    logger.info("Delayed cleanup executed via SQS delay.")

                if "Records" in body and body["Records"][0]["eventSource"] == "aws:s3":
                    record = body["Records"][0]
                    eventTime = record["eventTime"]
                    bucket_name = record["s3"]["bucket"]["name"]
                    object_key = record["s3"]["object"]["key"]
                    s3_imposm3_exp_path = f"s3://{bucket_name}/{object_key}"
                    file_name = os.path.basename(object_key)
                    logger.info(f"Event: {eventTime},{'##' * 60} ")
                    # Create a job based on infrastructure
                    if Config.TILER_CACHE_CLOUD_INFRASTRUCTURE == "aws":
                        create_kubernetes_job(s3_imposm3_exp_path, file_name)
                    elif Config.TILER_CACHE_CLOUD_INFRASTRUCTURE == "hetzner":
                        logger.info(f"No docker job ")

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
                            DelaySeconds=Config.DELAYED_CLEANUP_TIMER_SECONDS
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
    logger.info("Starting SQS message processing...")
    process_sqs_messages()
