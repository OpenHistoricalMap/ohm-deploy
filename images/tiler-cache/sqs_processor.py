import boto3
import time
import os
import json
import threading

from utils.s3_utils import compute_children_tiles, generate_tile_patterns, delete_folders_by_pattern
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


def cleanup_zoom_levels(s3_path, zoom_levels, bucket_name, path_file):
    """Executes the S3 cleanup process for specific zoom levels."""
    try:
        logger.info(
            f"Starting cleanup for S3 path: {s3_path}, zoom levels: {zoom_levels}, bucket: {bucket_name}"
        )

        # Compute child tiles
        tiles = compute_children_tiles(s3_path, zoom_levels)

        # Generate patterns for deletion
        patterns = generate_tile_patterns(tiles)
        logger.info(f"Generated tile patterns for deletion: {patterns}")

        # Delete folders based on patterns
        delete_folders_by_pattern(bucket_name, patterns, path_file)
        logger.info("S3 cleanup completed successfully.")

    except Exception as e:
        logger.error(f"Error during cleanup: {e}")
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
                    logger.error("PostgreSQL database is down. Retrying in 1 minute...")
                    time.sleep(60)
                    continue

                # Wait until job limit is under threshold
                while get_active_jobs_count() >= Config.MAX_ACTIVE_JOBS:
                    logger.warning(
                        f"Max active jobs limit ({Config.MAX_ACTIVE_JOBS}) reached. Waiting 1 minute..."
                    )
                    time.sleep(60)

                # Parse the SQS message
                body = json.loads(message["Body"])

                if "Records" in body and body["Records"][0]["eventSource"] == "aws:s3":
                    record = body["Records"][0]
                    bucket_name = record["s3"]["bucket"]["name"]
                    object_key = record["s3"]["object"]["key"]

                    file_url = f"s3://{bucket_name}/{object_key}"
                    file_name = os.path.basename(object_key)
                    print(file_url)
                    logger.info(f"Processing S3 event for file: {file_url}")

                    # Create a job based on infrastructure
                    if Config.TILER_CACHE_CLOUD_INFRASTRUCTURE == "aws":
                        create_kubernetes_job(file_url, file_name)
                    elif Config.TILER_CACHE_CLOUD_INFRASTRUCTURE == "hetzner":
                        # create_docker_job(file_url, file_name)
                        logger.info(f"Docker wont start")

                    # Cleanup old zoom levels asynchronously
                    cleanup_thread = threading.Thread(
                        target=cleanup_zoom_levels,
                        args=(
                            file_url,
                            Config.ZOOM_LEVELS_TO_DELETE,
                            Config.S3_BUCKET_CACHE_TILER,
                            Config.S3_BUCKET_PATH_FILES,
                        ),
                    )
                    cleanup_thread.start()

                elif "Event" in body and body["Event"] == "s3:TestEvent":
                    logger.info("Test event detected. Ignoring...")

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
