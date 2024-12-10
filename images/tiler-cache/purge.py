import boto3
import time
from kubernetes import client, config
import os
import json
from datetime import datetime, timezone, timedelta
import logging
from utils import check_tiler_db_postgres_status
from s3_cleanup import compute_children_tiles, generate_tile_patterns, delete_folders_by_pattern

logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)

# Environment variables
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
NAMESPACE = os.getenv("NAMESPACE", "default")
SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "default-queue-url")
REGION_NAME = os.getenv("REGION_NAME", "us-east-1")
DOCKER_IMAGE = os.getenv(
    "DOCKER_IMAGE",
    "ghcr.io/openhistoricalmap/tiler-server:0.0.1-0.dev.git.1780.h62561a8",
)
NODEGROUP_TYPE = os.getenv("NODEGROUP_TYPE", "job_large")
MAX_ACTIVE_JOBS = int(os.getenv("MAX_ACTIVE_JOBS", 2))
DELETE_OLD_JOBS_AGE = int(os.getenv("DELETE_OLD_JOBS_AGE", 3600))  # default 1 hour

# Tiler cache purge and seed settings
EXECUTE_PURGE = os.getenv("EXECUTE_PURGE", "true")
EXECUTE_SEED = os.getenv("EXECUTE_SEED", "true")
# zoom
PURGE_MIN_ZOOM = os.getenv("PURGE_MIN_ZOOM", 8)
PURGE_MAX_ZOOM = os.getenv("PURGE_MAX_ZOOM", 20)
SEED_MIN_ZOOM = os.getenv("SEED_MIN_ZOOM", 8)
SEED_MAX_ZOOM = os.getenv("SEED_MAX_ZOOM", 14)
## concurrency
SEED_CONCURRENCY = os.getenv("SEED_CONCURRENCY", 16)
PURGE_CONCURRENCY = os.getenv("PURGE_CONCURRENCY", 16)

JOB_NAME_PREFIX = f"{ENVIRONMENT}-tiler-cache-purge-seed"
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_PORT = int(os.getenv("POSTGRES_PORT", 5432))
POSTGRES_DB = os.getenv("POSTGRES_DB", "postgres")
POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "password")

ZOOM_LEVELS_TO_DELETE = list(map(int, os.getenv("ZOOM_LEVELS_TO_DELETE", "18,19,20").split(",")))
S3_BUCKET_CACHE_TILER = os.getenv("S3_BUCKET_CACHE_TILER", "tiler-cache-staging")
S3_BUCKET_PATH_FILES = os.getenv("S3_BUCKET_PATH_FILES", "mnt/data/osm")

# Initialize Kubernetes and AWS clients
sqs = boto3.client("sqs", region_name=REGION_NAME)
config.load_incluster_config()
batch_v1 = client.BatchV1Api()
core_v1 = client.CoreV1Api()


def get_active_jobs_count():
    """Returns the number of active jobs in the namespace with names starting with 'tiler-purge-seed-'."""
    logging.info("Checking active or pending jobs...")
    jobs = batch_v1.list_namespaced_job(namespace=NAMESPACE)
    active_jobs_count = 0

    for job in jobs.items:
        if not job.metadata.name.startswith(JOB_NAME_PREFIX):
            continue

        label_selector = f"job-name={job.metadata.name}"
        pods = core_v1.list_namespaced_pod(namespace=NAMESPACE, label_selector=label_selector)

        for pod in pods.items:
            if pod.status.phase in [
                "Pending",
                "PodInitializing",
                "ContainerCreating",
                "Running",
                "Error",
            ]:
                logging.debug(f"Job '{job.metadata.name}' has a pod in {pod.status.phase} state.")
                active_jobs_count += 1
                break

    logging.info(f"Total active or pending jobs: {active_jobs_count}")
    return active_jobs_count


def create_kubernetes_job(file_url, file_name):
    """Create a Kubernetes Job to process a file."""
    configmap_tiler_server = f"{ENVIRONMENT}-tiler-server-cm"
    configmap_tiler_db = f"{ENVIRONMENT}-tiler-db-cm"

    job_name = f"{JOB_NAME_PREFIX}-{file_name}"
    job_manifest = {
        "apiVersion": "batch/v1",
        "kind": "Job",
        "metadata": {"name": job_name},
        "spec": {
            "ttlSecondsAfterFinished": DELETE_OLD_JOBS_AGE,
            "template": {
                "spec": {
                    "nodeSelector": {"nodegroup_type": NODEGROUP_TYPE},
                    "containers": [
                        {
                            "name": "tiler-purge-seed",
                            "image": DOCKER_IMAGE,
                            "command": ["sh", "./purge_and_seed.sh"],
                            "envFrom": [{"configMapRef": {"name": configmap_tiler_server}},{"configMapRef": {"name": configmap_tiler_db}}],
                            "env": [
                                {"name": "IMPOSM_EXPIRED_FILE", "value": file_url},
                                {"name": "EXECUTE_PURGE", "value": str(EXECUTE_PURGE)},
                                {"name": "EXECUTE_SEED", "value": str(EXECUTE_SEED)},
                                {"name": "PURGE_MIN_ZOOM", "value": str(PURGE_MIN_ZOOM)},
                                {"name": "PURGE_MAX_ZOOM", "value": str(PURGE_MAX_ZOOM)},
                                {"name": "SEED_MIN_ZOOM", "value": str(SEED_MIN_ZOOM)},
                                {"name": "SEED_MAX_ZOOM", "value": str(SEED_MAX_ZOOM)},
                                {"name": "SEED_CONCURRENCY", "value": str(SEED_CONCURRENCY)},
                                {"name": "PURGE_CONCURRENCY", "value": str(PURGE_CONCURRENCY)},
                            ],
                        }
                    ],
                    "restartPolicy": "Never",
                }
            },
            "backoffLimit": 3,
        },
    }

    try:
        batch_v1.create_namespaced_job(namespace=NAMESPACE, body=job_manifest)
        logging.info(f"Kubernetes Job '{job_name}' created for file: {file_url}")
    except Exception as e:
        logging.error(f"Failed to create Kubernetes Job '{job_name}': {e}")



def cleanup_zoom_levels(s3_path, zoom_levels, bucket_name, path_file):
    """
    Executes the S3 cleanup process for specific zoom levels.
    
    Args:
        s3_path (str): Path to the S3 tiles file.
        zoom_levels (list): List of zoom levels to process.
        bucket_name (str): Name of the S3 bucket for deletion.

    Returns:
        None
    """
    try:
        logging.info(f"Starting cleanup for S3 path: {s3_path}, zoom levels: {zoom_levels}, bucket: {bucket_name}")

        # Compute child tiles
        tiles = compute_children_tiles(s3_path, zoom_levels)

        # Generate patterns for deletion
        patterns = generate_tile_patterns(tiles)
        logging.info(f"Generated tile patterns for deletion: {patterns}")

        # Delete folders based on patterns
        delete_folders_by_pattern(bucket_name, patterns, path_file)
        logging.info("S3 cleanup completed successfully.")

    except Exception as e:
        logging.error(f"Error during cleanup: {e}")
        raise

def process_sqs_messages():
    """Process messages from the SQS queue and create Kubernetes Jobs for each file."""
    while True:
        response = sqs.receive_message(
            QueueUrl=SQS_QUEUE_URL,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=10,
            AttributeNames=["All"],
            MessageAttributeNames=["All"],
        )

        messages = response.get("Messages", [])
        if not messages:
            logging.info("No messages in the queue. Retrying in 5 seconds...")
            time.sleep(5)
            continue

        for message in messages:
            try:
                # Check PostgreSQL status
                if not check_tiler_db_postgres_status():
                    logging.error("PostgreSQL database is down. Retrying in 1 minute...")
                    time.sleep(60)
                    continue

                # Check active job count before processing
                while get_active_jobs_count() >= MAX_ACTIVE_JOBS:
                    logging.warning(
                        f"Max active jobs limit ({MAX_ACTIVE_JOBS}) reached. Waiting 1 minute..."
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

                    logging.info(f"Processing S3 event for file: {file_url}")

                    # Create a Kubernetes job
                    create_kubernetes_job(file_url, file_name)

                    # Remove zoom levels 18,19,20
                    cleanup_zoom_levels(file_url, ZOOM_LEVELS_TO_DELETE, S3_BUCKET_CACHE_TILER, S3_BUCKET_PATH_FILES)

                elif "Event" in body and body["Event"] == "s3:TestEvent":
                    logging.info("Test event detected. Ignoring...")

                # Delete the processed message
                sqs.delete_message(
                    QueueUrl=SQS_QUEUE_URL,
                    ReceiptHandle=message["ReceiptHandle"],
                )
                logging.info(f"Message processed and deleted: {message['MessageId']}")

            except Exception as e:
                logging.error(f"Error processing message: {e}")

        time.sleep(10)


if __name__ == "__main__":
    logging.info("Starting SQS message processing...")
    process_sqs_messages()
