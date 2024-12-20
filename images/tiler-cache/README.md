# Tiler Cache purging and seeding

This is a container that includes scripts to perform purge and seed operations. Each script must run on a different instance.

# Seeding Tiles

This script is designed to minimize latency when users interact with OHM tiles by efficiently generating and seeding tiles across specified zoom levels. Running the entire world dataset may take a significant amount of time to generate the tile cache due to the large volume of data. so that the reson we prioritize certain areas. 

The script processes a GeoJSON file containing areas where tile cache generation is required and seeds tiles for OHM, ensuring optimized performance.

Usage

```sh
# The URL of the GeoJSON file specifying the areas where tile seeding is required.
export GEOJSON_URL: https://osmseed-dev.s3.us-east-1.amazonaws.com/tiler/wold-usa-eu.geojson
export ZOOM_LEVELS: '7,8,9,10' # The zoom levels for which tiles need to be seeded.
export CONCURRENCY: 32 # The number of parallel processes to use for generating cache tiles.
export S3_BUCKET: osmseed-dev # The S3 bucket where output statistics (e.g., seeding duration) will be stored.
export OUTPUT_FILE: /logs/tiler_benchmark.log #The path to a CSV file for logging benchmarking results and tracking database performance.

python seed.py
```

### Tiler Seed CronJob

Chart `ohm/templates/tiler-cache-seed/cronjob.yaml` CronJob is designed to execute scheduled tasks for seeding cache. It runs the script `seed.py`, primarily targeting zoom levels 7 to 10. Additionally, the job seeds tiles for zoom levels 0 to 6 every 24 hours to ensure that lower zoom levels remain updated, minimizing latency for users navigating the map.


# Purging Tiles

This script processes an AWS SQS queue and launches a container to handle the purging and seeding of the tiler cache for specific imposm expired files. The script efficiently purges cache tiles within zoom levels 8 to 17. Due to the significant time required to purge higher zoom levels (18, 19, and 20), the script includes a separate section to directly delete these tiles from S3. By following specific patterns, this method is far more efficient than using the tiler purge process for zoom levels 18, 19, and 20.


```sh
# Environment settings
ENVIRONMENT = "staging"  # Environment where the script is executed (e.g., staging or production).
NAMESPACE = "default"  # Kubernetes namespace where the tiler cache pods will be triggered.
SQS_QUEUE_URL = "https://sqs.us-east-1.amazonaws.com/123456789/tiler-imposm3-expired-files"  # AWS SQS queue URL for processing expired tiles.
REGION_NAME = "us-east-1"  # AWS region where the deployment is hosted.
DOCKER_IMAGE = "ghcr.io/openhistoricalmap/tiler-server:0.0.1-0.dev.git.1780.h62561a8"  # Docker image for the tiler server to handle cache purging and seeding.
NODEGROUP_TYPE = "job_large"  # Node group label where the cache cleaning pods will be executed.
MAX_ACTIVE_JOBS = 5  # Maximum number of jobs allowed to run in parallel.
DELETE_OLD_JOBS_AGE = 3600  # Time in seconds after which old jobs will be deleted.

# Tiler cache purge and seed settings
EXECUTE_PURGE = "true"  # Whether to execute the purge process.
EXECUTE_SEED = "true"  # Whether to execute the seed process.

# Zoom level configurations for cache management
PURGE_MIN_ZOOM = 8  # Minimum zoom level for cache purging.
PURGE_MAX_ZOOM = 20  # Maximum zoom level for cache purging.
SEED_MIN_ZOOM = 8  # Minimum zoom level for tile seeding.
SEED_MAX_ZOOM = 14  # Maximum zoom level for tile seeding.

# Concurrency settings
SEED_CONCURRENCY = 16  # Number of parallel processes for seeding tiles.
PURGE_CONCURRENCY = 16  # Number of parallel processes for purging tiles.

# PostgreSQL settings for the tiler database
POSTGRES_HOST = "localhost"  # Hostname of the PostgreSQL database.
POSTGRES_PORT = 5432  # Port for the PostgreSQL database.
POSTGRES_DB = "postgres"  # Name of the PostgreSQL database.
POSTGRES_USER = "postgres"  # Username for the PostgreSQL database.
POSTGRES_PASSWORD = "password"  # Password for the PostgreSQL database.

# S3 settings for managing tile data
ZOOM_LEVELS_TO_DELETE = "18,19,20"  # Zoom levels for which cache tiles will be deleted directly from S3.
S3_BUCKET_CACHE_TILER = "tiler-cache-staging"  # S3 bucket where the tile cache is stored.
S3_BUCKET_PATH_FILES = "mnt/data/osm"  # Path within the S3 bucket for tiles to be deleted.

python purge.py

```


### Tiler Purge Deployment

Deployment ``ohm/templates/tiler-cache-purge/deployment.yaml` is responsible for running the script `purge.py`, which handles purging tiles across different zoom levels. To execute this deployment, it is necessary to create a service account and attach it to the deployment. For example:

```yaml
# Create a ServiceAccount for managing Jobs and associated Pods
apiVersion: v1
kind: ServiceAccount
metadata:
  name: job-service-account
  namespace: default
---
# Create a ClusterRole with permissions for Jobs and Pods
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: job-manager-role
rules:
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["create", "list", "delete"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["list", "get"]
---
# Bind the ClusterRole to the ServiceAccount
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: job-manager-role-binding
subjects:
- kind: ServiceAccount
  name: job-service-account
  namespace: default
roleRef:
  kind: ClusterRole
  name: job-manager-role
  apiGroup: rbac.authorization.k8s.io
```