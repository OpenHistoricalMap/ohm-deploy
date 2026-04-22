# Tiler Cache Management Container

This repository contains a containerized application that invalidates the map tile cache by sending **BAN** requests to Varnish when imposm3 produces expire files.

It is designed to run under Docker Compose (Hetzner stack). It listens to an AWS SQS queue fed by S3 events on the imposm3 expire-file bucket and, for each file, expands the affected tiles and bans them in Varnish.

### Core Features

*   **Varnish BAN invalidation**: Listens to an SQS queue for notifications about new imposm3 expire files and issues BAN requests to Varnish so the next request repopulates the cache from Martin.
*   **Delayed retries**: Optionally re-runs the BAN invalidation after 15 min / 1 h / 2 h using SQS-delayed messages, to catch late-reaching tiles.
*   **Changeset / point endpoint**: Exposes `/clean-cache` to invalidate tiles for an OHM changeset bbox or a `lat/lon + buffer_meters`.

## Configuration

The container is configured entirely through environment variables. All variables are optional and have default values.

| Variable | Description | Default Value |
| :--- | :--- | :--- |
| **General & SQS** |
| `ENVIRONMENT` | The operating environment (e.g., `development`, `staging`, `production`). | `development` |
| `SQS_QUEUE_URL` | The URL of the AWS SQS queue to listen to for expire-file events. | `default-queue-url` |
| `AWS_REGION_NAME` | The AWS region for the SQS queue. | `us-east-1` |
| **Zoom Levels** |
| `ZOOM_LEVELS_TO_DELETE` | Comma-separated zoom levels to invalidate via Varnish BAN. | `10,11,12,13,14,15,16,17,18,19,20` |
| **Varnish** |
| `VARNISH_URL` | Base URL of the Varnish instance receiving BAN requests. | `http://varnish:6081` |
| `VARNISH_BAN_TIMEOUT` | Timeout (seconds) for BAN HTTP requests. | `5` |
| `VARNISH_TILE_URL_PREFIX` | URL prefix used when matching tile paths in BAN regex. | `/maps/ohm` |
| `VARNISH_MAX_TILES_PER_REQUEST` | Max tile patterns per BAN request. | `200` |
| **PostgreSQL Database** |
| `POSTGRES_HOST` | Hostname of the PostgreSQL database. | `localhost` |
| `POSTGRES_PORT` | Port for the PostgreSQL database. | `5432` |
| `POSTGRES_DB` | Name of the PostgreSQL database. | `postgres` |
| `POSTGRES_USER` | Username for the PostgreSQL database. | `postgres` |
| `POSTGRES_PASSWORD` | Password for the PostgreSQL database. | `password` |
| **Cleanup** |
| `ENABLE_DELAYED_CLEANUP` | Enable delayed BAN retries (15 min / 1 h / 2 h). Set to `"true"` to enable. | `true` |

## Usage

```sh
python sqs_processor.py
```
This script listens to the SQS queue for S3 events on the imposm3 expire-file bucket. For each new file it reads the expired tile list and issues BAN request(s) to Varnish.

To run this script, you must configure the SQS and Postgres environment variables, plus `VARNISH_URL` if your Varnish is not reachable at the default.

### Delayed Cleanup System

The system implements a multi-phase invalidation strategy:

1. **Immediate BAN**: Executed immediately when an expire-file S3 event arrives.
2. **Delayed retries (15 min / 1 h / 2 h)**: Scheduled via SQS `DelaySeconds` (for ≤15 min) or timestamp-based re-checking (for longer delays, since SQS max delay is 15 minutes).

Delayed retries can be toggled with `ENABLE_DELAYED_CLEANUP`. They cover tiles whose rendering dependencies (e.g. materialised views, neighbouring features) take some time to settle.

### Required Cloud Permissions (IAM)

The pod/container needs AWS IAM permissions to:

```
sqs:ReceiveMessage
sqs:DeleteMessage
sqs:SendMessage
```

`SendMessage` is used to schedule delayed BAN retries back onto the same queue.
