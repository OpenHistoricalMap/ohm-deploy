import boto3
import time
from kubernetes import client, config
import os
import json
from datetime import datetime, timezone, timedelta
import logging
from utils import (
    check_tiler_db_postgres_status
)

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
    "ghcr.io/openhistoricalmap/tiler-server:0.0.1-0.dev.git.1734.h5b4d15d",
)
NODEGROUP_TYPE = os.getenv("NODEGROUP_TYPE", "job_large")
MAX_ACTIVE_JOBS = int(os.getenv("MAX_ACTIVE_JOBS", 2))
DELETE_OLD_JOBS_AGE = int(os.getenv("DELETE_OLD_JOBS_AGE", 86400)) # default 1 day
MIN_ZOOM = os.getenv("MIN_ZOOM", 8)
MAX_ZOOM = os.getenv("MAX_ZOOM", 16)
JOB_NAME_PREFIX = f"{ENVIRONMENT}-tiler-cache-purge-seed"
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_PORT = int(os.getenv("POSTGRES_PORT", 5432))
POSTGRES_DB = os.getenv("POSTGRES_DB", "postgres")
POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "password")

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
    config_map_name = f"{ENVIRONMENT}-tiler-server-cm"
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
                            "envFrom": [{"configMapRef": {"name": config_map_name}}],
                            "env": [
                                {"name": "IMPOSM_EXPIRED_FILE", "value": file_url},
                                {"name": "MIN_ZOOM", "value": str(MIN_ZOOM)},
                                {"name": "MAX_ZOOM", "value": str(MAX_ZOOM)},
                            ],
                        }
                    ],
                    "restartPolicy": "Never",
                }
            },
            "backoffLimit": 0,
        },
    }

    try:
        batch_v1.create_namespaced_job(namespace=NAMESPACE, body=job_manifest)
        logging.info(f"Kubernetes Job '{job_name}' created for file: {file_url}")
    except Exception as e:
        logging.error(f"Failed to create Kubernetes Job '{job_name}': {e}")


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