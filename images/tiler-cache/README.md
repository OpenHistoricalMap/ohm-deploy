# Tiler Cache Management Container

This repository contains a containerized application designed to manage the tile cache for a map server. It provides scripts to **purging** (deleting outdated tiles based on notifications).

The system is designed to run in a Kubernetes environment or Docker , leveraging AWS SQS for message queuing and interacting directly with S3 for efficient cache management.

### Core Features

*   **Tile Purging**: Listens to an SQS queue for messages about expired tiles and deletes the corresponding cache tiles directly from S3 based on the expired data's coverage.
*   **High-Zoom S3 Deletion**: Includes an optimized process to directly delete tiles from S3 for high zoom levels (18-20), which is significantly faster than traditional purging methods.
*   **Multi-Cloud Support**: Configurable to work with both AWS S3 and other S3-compatible object storage services like Hetzner.

## Configuration

The container is configured entirely through environment variables. All variables are optional and have default values.

| Variable | Description | Default Value |
| :--- | :--- | :--- |
| **General & SQS** |
| `ENVIRONMENT` | The operating environment (e.g., `development`, `staging`, `production`). | `development` |
| `SQS_QUEUE_URL` | The URL of the AWS SQS queue to listen to for purge messages. | `default-queue-url` |
| `AWS_REGION_NAME` | The AWS region for the SQS queue. | `us-east-1` |
| **Tiler Cache Operations** |
| `EXECUTE_PURGE` | Set to `"true"` to enable the tile purging process. | `true` |
| **Zoom Levels** |
| `PURGE_MIN_ZOOM` | The minimum zoom level to purge. | `8` |
| `PURGE_MAX_ZOOM` | The maximum zoom level to purge. | `20` |
| `ZOOM_LEVELS_TO_DELETE` | A comma-separated list of high zoom levels to delete directly from S3. | `18,19,20` |
| **Concurrency** |
| `PURGE_CONCURRENCY` | The number of parallel processes to use for purging tiles. | `16` |
| **S3 Settings** |
| `S3_BUCKET_CACHE_TILER` | The S3 bucket where the tile cache is stored. | `tiler-cache-staging` |
| `S3_BUCKET_PATH_FILES` | The base path(s) in the S3 bucket for tiles to be deleted (comma-separated). | `mnt/data/osm,mnt/data/ohm_admin` |
| **Cloud Infrastructure & Credentials** |
| `TILER_CACHE_CLOUD_INFRASTRUCTURE` | The cloud provider for S3. Can be `aws` or `hetzner`. | `aws` |
| `TILER_CACHE_AWS_ACCESS_KEY_ID` | The access key for your S3-compatible storage (required for `hetzner`). | `""` |
| `TILER_CACHE_AWS_SECRET_ACCESS_KEY` | The secret key for your S3-compatible storage (required for `hetzner`). | `""` |
| `TILER_CACHE_AWS_ENDPOINT` | The S3 endpoint URL. Use the default for AWS, or a custom one for `hetzner`. | `https://s3.amazonaws.com` |
| `TILER_CACHE_REGION` | The region for the S3-compatible storage. | `us-east-1` |
| `TILER_CACHE_BUCKET` | The name of the S3 bucket for the tiler cache. | `none` |
| **PostgreSQL Database** |
| `POSTGRES_HOST` | Hostname of the PostgreSQL database. | `localhost` |
| `POSTGRES_PORT` | Port for the PostgreSQL database. | `5432` |
| `POSTGRES_DB` | Name of the PostgreSQL database. | `postgres` |
| `POSTGRES_USER` | Username for the PostgreSQL database. | `postgres` |
| `POSTGRES_PASSWORD` | Password for the PostgreSQL database. | `password` |
| **Cleanup** |
| `DELAYED_CLEANUP_TIMER_SECONDS` | Delay in seconds before cleaning up resources after a job. | `3600` |

## Usage

```sh
python sqs_processor.py
```
This script  listens to an SQS queue for messages about expired map data. Upon receiving a message, it calculates the affected tile coverage and deletes the corresponding tiles directly from the S3 bucket.

To run this script, you must configure all the required environment variables, especially those related to SQS and S3.

### Required Cloud Permissions (IAM)
Since the script no longer creates Kubernetes jobs, it does not require RBAC permissions to manage cluster resources. Instead, the service account running the purge.py pod needs AWS IAM permissions to interact with SQS and S3.

Ensure the pod's service account has an associated IAM role with permissions for actions such as:

```
sqs:ReceiveMessage
sqs:DeleteMessage
s3:DeleteObject
s3:ListBucket
```