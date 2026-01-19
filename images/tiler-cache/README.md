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
| `ENABLE_DELAYED_CLEANUP` | Enable delayed cleanup operations (15 minutes and 1 hour). Set to `"true"` to enable. | `true` |
| `DELAYED_CLEANUP_TIMER_SECONDS` | Delay in seconds before cleaning up resources after a job (legacy, kept for backward compatibility). | `3600` |

## Usage

```sh
python sqs_processor.py
```
This script  listens to an SQS queue for messages about expired map data. Upon receiving a message, it calculates the affected tile coverage and deletes the corresponding tiles directly from the S3 bucket.

To run this script, you must configure all the required environment variables, especially those related to SQS and S3.

### Delayed Cleanup System

The system implements a three-phase cleanup strategy:

1. **Immediate Cleanup**: Executed immediately when an S3 expiration file is detected
2. **15-Minute Delayed Cleanup**: Scheduled via SQS with a 15-minute delay (using SQS `DelaySeconds`)
3. **1-Hour Delayed Cleanup**: Scheduled via SQS with a 1-hour delay (using timestamp-based checking since SQS max delay is 15 minutes)

The delayed cleanups can be enabled/disabled using the `ENABLE_DELAYED_CLEANUP` environment variable. When enabled, both delayed cleanups are automatically scheduled after the immediate cleanup completes.

**Note**: The 1-hour cleanup uses a timestamp in the message body to track when it was originally scheduled. When the message is processed (after the 15-minute SQS delay), the system checks if 1 hour has actually passed before executing the cleanup.

### Required Cloud Permissions (IAM)
Since the script no longer creates Kubernetes jobs, it does not require RBAC permissions to manage cluster resources. Instead, the service account running the purge.py pod needs AWS IAM permissions to interact with SQS and S3.

Ensure the pod's service account has an associated IAM role with permissions for actions such as:

```
sqs:ReceiveMessage
sqs:DeleteMessage
s3:DeleteObject
s3:ListBucket
```