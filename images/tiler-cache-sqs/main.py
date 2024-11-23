import boto3
import time
from kubernetes import client, config
import os
import json
from datetime import datetime, timezone, timedelta
import logging

# Configure logging
logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)

# Environment variables
ENVIRONMENT = os.getenv("ENVIRONMENT", "staging")
NAMESPACE = os.getenv("NAMESPACE", "default")
SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "default-queue-url")
REGION_NAME = os.getenv("REGION_NAME", "us-east-1")
DOCKER_IMAGE = os.getenv("DOCKER_IMAGE", "ghcr.io/openhistoricalmap/tiler-server:0.0.1-0.dev.git.1735.h825f665")
NODEGROUP_TYPE = os.getenv("NODEGROUP_TYPE", "job_large")
MAX_ACTIVE_JOBS = int(os.getenv("MAX_ACTIVE_JOBS", 2))
DELETE_OLD_JOBS_AGE = int(os.getenv("DELETE_OLD_JOBS_AGE", 86400))

MIN_ZOOM = os.getenv("MIN_ZOOM", 8)
MAX_ZOOM = os.getenv("MAX_ZOOM", 16)

sqs = boto3.client("sqs", region_name=REGION_NAME)
config.load_incluster_config()
batch_v1 = client.BatchV1Api()
core_v1 = client.CoreV1Api()

def get_active_jobs_count():
    """Returns the number of jobs in the namespace with names starting with 'tiler-purge-seed-'."""
    logging.info("Checking the number of active or pending jobs...")
    jobs = batch_v1.list_namespaced_job(namespace=NAMESPACE)
    active_jobs_count = 0

    for job in jobs.items:
        if not job.metadata.name.startswith("tiler-purge-seed-"):
            continue
        label_selector = f"job-name={job.metadata.name}"
        pods = core_v1.list_namespaced_pod(namespace=NAMESPACE, label_selector=label_selector)

        for pod in pods.items:
            if pod.status.phase in ["Running", "Pending"]:
                logging.debug(f"Job '{job.metadata.name}' has a pod in {pod.status.phase} state.")
                active_jobs_count += 1
                break

    logging.info(f"Active or pending jobs count: {active_jobs_count}")
    return active_jobs_count

def create_kubernetes_job(file_url, file_name):
    """Create a Kubernetes Job to process a file."""
    config_map_name = f"{ENVIRONMENT}-tiler-server-cm"
    job_name = f"tiler-purge-seed-{file_name}"
    job_manifest = {
        "apiVersion": "batch/v1",
        "kind": "Job",
        "metadata": {"name": job_name},
        "spec": {
            "ttlSecondsAfterFinished": DELETE_OLD_JOBS_AGE, 
            "template": {
                "spec": {
                    "nodeSelector": {
                        "nodegroup_type": NODEGROUP_TYPE
                    },
                    "containers": [
                        {
                            "name": "tiler-purge-seed",
                            "image": DOCKER_IMAGE,
                            "command": ["sh", "./purge_and_seed.sh"],
                            "envFrom": [
                                {"configMapRef": {"name": config_map_name}},
                            ],
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
            "backoffLimit": 1,
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

        # Wait for active jobs to drop below the limit
        while get_active_jobs_count() >= MAX_ACTIVE_JOBS:
            logging.warning(f"Active jobs limit reached ({MAX_ACTIVE_JOBS}). Waiting...")
            time.sleep(60)

        # Fetch messages from SQS
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
                body = json.loads(message["Body"])

                if "Records" in body and body["Records"][0]["eventSource"] == "aws:s3":
                    record = body["Records"][0]
                    bucket_name = record["s3"]["bucket"]["name"]
                    object_key = record["s3"]["object"]["key"]

                    file_url = f"s3://{bucket_name}/{object_key}"
                    file_name = os.path.basename(object_key)

                    logging.info(f"Processing S3 event for file: {file_url}")

                    create_kubernetes_job(file_url, file_name)

                elif "Event" in body and body["Event"] == "s3:TestEvent":
                    logging.info("Test event detected. Ignoring...")

                sqs.delete_message(
                    QueueUrl=SQS_QUEUE_URL,
                    ReceiptHandle=message["ReceiptHandle"],
                )
                logging.info(f"Message processed and deleted: {message['MessageId']}")

            except Exception as e:
                logging.error(f"Error processing message: {e}")
                continue

        time.sleep(10)

if __name__ == "__main__":
    logging.info("Starting SQS message processing...")
    process_sqs_messages()
