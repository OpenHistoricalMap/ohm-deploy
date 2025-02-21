import logging
from kubernetes import client, config
from config import Config
from utils.utils import get_logger,get_purge_and_seed_commands
logger = get_logger()

def init_kubernetes_clients():
    """Initialize Kubernetes API clients globally."""
    try:
        config.load_incluster_config()
        logger.info("Loaded in-cluster Kubernetes configuration.")
    except config.ConfigException:
        logger.error("Failed to load in-cluster config. Ensure this script runs inside Kubernetes.")
        return None, None

    return client.BatchV1Api(), client.CoreV1Api()

# Global Kubernetes API clients
batch_v1, core_v1 = init_kubernetes_clients()

def get_active_k8s_jobs_count(namespace, job_name_prefix):
    """
    Returns the number of active jobs in the namespace with names starting with 'JOB_NAME_PREFIX'.
    
    Args:
        namespace (str): The Kubernetes namespace to check.
        job_name_prefix (str): Prefix to filter relevant jobs.
    
    Returns:
        int: Number of active or pending jobs.
    """
    if not batch_v1 or not core_v1:
        logger.error("Kubernetes API clients are not initialized.")
        return 0

    logger.info("Checking active or pending jobs in Kubernetes...")
    active_jobs_count = 0

    try:
        jobs = batch_v1.list_namespaced_job(namespace=namespace)

        for job in jobs.items:
            if not job.metadata.name.startswith(job_name_prefix):
                continue

            label_selector = f"job-name={job.metadata.name}"
            pods = core_v1.list_namespaced_pod(namespace=namespace, label_selector=label_selector)

            for pod in pods.items:
                if pod.status.phase in [
                    "Pending",
                    "PodInitializing",
                    "ContainerCreating",
                    "Running",
                    "Error",
                ]:
                    logger.debug(f"Job '{job.metadata.name}' has a pod in {pod.status.phase} state.")
                    active_jobs_count += 1
                    break

    except Exception as e:
        logger.error(f"Error while fetching Kubernetes jobs: {e}")
        return 0

    logger.info(f"Total active or pending jobs: {active_jobs_count}")
    return active_jobs_count


def create_kubernetes_job(file_url, file_name):
    """Create a Kubernetes Job to process a file."""
    configmap_tiler_server = f"{Config.ENVIRONMENT}-tiler-server-cm"
    configmap_tiler_db = f"{Config.ENVIRONMENT}-tiler-db-cm"
    job_name = f"{Config.JOB_NAME_PREFIX}-{file_name.replace('.', '-')}"
    shell_commands = get_purge_and_seed_commands()

    job_manifest = {
        "apiVersion": "batch/v1",
        "kind": "Job",
        "metadata": {"name": job_name},
        "spec": {
            "ttlSecondsAfterFinished": Config.DELETE_OLD_JOBS_AGE,
            "template": {
                "spec": {
                    "nodeSelector": {"nodegroup_type": Config.NODEGROUP_TYPE},
                    "containers": [
                        {
                            "name": "tiler-purge-seed",
                            "image": Config.DOCKER_IMAGE,
                            "command": ["bash", "-c", shell_commands],
                            "envFrom": [{"configMapRef": {"name": configmap_tiler_server}},{"configMapRef": {"name": configmap_tiler_db}}],
                            "env": [
                                {"name": "IMPOSM_EXPIRED_FILE", "value": file_url},
                                {"name": "EXECUTE_PURGE", "value": str(Config.EXECUTE_PURGE)},
                                {"name": "EXECUTE_SEED", "value": str(Config.EXECUTE_SEED)},
                                {"name": "PURGE_MIN_ZOOM", "value": str(Config.PURGE_MIN_ZOOM)},
                                {"name": "PURGE_MAX_ZOOM", "value": str(Config.PURGE_MAX_ZOOM)},
                                {"name": "SEED_MIN_ZOOM", "value": str(Config.SEED_MIN_ZOOM)},
                                {"name": "SEED_MAX_ZOOM", "value": str(Config.SEED_MAX_ZOOM)},
                                {"name": "SEED_CONCURRENCY", "value": str(Config.SEED_CONCURRENCY)},
                                {"name": "PURGE_CONCURRENCY", "value": str(Config.PURGE_CONCURRENCY)},
                            ],
                        }
                    ],
                    "restartPolicy": "Never",
                }
            },
            "backoffLimit": 4,
        },
    }
    print("##"*20)
    print(job_manifest)
    print("##"*20)

    try:
        batch_v1.create_namespaced_job(namespace=Config.NAMESPACE, body=job_manifest)
        logger.info(f"Kubernetes Job '{job_name}' created for file: {file_url}")
    except Exception as e:
        logger.error(f"Failed to create Kubernetes Job '{job_name}': {e}")
