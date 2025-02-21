import docker
import logging
from config import Config
from utils.utils import get_logger, get_purge_and_seed_commands
logger = get_logger("docker_jobs")


def get_active_docker_jobs_count(job_name_prefix):
    """Returns the number of active Docker containers with names starting with '*-tiler-purge-'."""
    logger.info("Checking active Docker containers...")

    client = docker.from_env()
    active_containers_count = 0

    containers = client.containers.list(filters={"status": "running"})

    for container in containers:
        container_name = container.name

        if container_name.startswith(job_name_prefix):
            logger.debug(f"Found active container: {container_name}")
            active_containers_count += 1

    logger.info(f"Total active Docker jobs: {active_containers_count}")
    return active_containers_count



def create_docker_job(file_url, file_name):
    """
    Creates and starts a Docker container to process the given file.

    Args:
        file_url (str): S3 or local file path to be processed.
        file_name (str): The name of the file.

    Returns:
        str: The container ID if successfully created, else None.
    """
    try:
        logger.info(f"Starting Docker job for file: {file_url}")

        # Initialize Docker client
        client = docker.from_env()

        # Define container name
        container_name = f"{Config.JOB_NAME_PREFIX}-{file_name.replace('.', '-')}"

        # Run Docker container with necessary environment variables
        container = client.containers.run(
            image=Config.DOCKER_IMAGE,
            name=container_name,
            detach=True,  # Run in the background
            environment={
                "IMPOSM_EXPIRED_FILE": file_url,
                "EXECUTE_PURGE": str(Config.EXECUTE_PURGE),
                "EXECUTE_SEED": str(Config.EXECUTE_SEED),
                "PURGE_MIN_ZOOM": str(Config.PURGE_MIN_ZOOM),
                "PURGE_MAX_ZOOM": str(Config.PURGE_MAX_ZOOM),
                "SEED_MIN_ZOOM": str(Config.SEED_MIN_ZOOM),
                "SEED_MAX_ZOOM": str(Config.SEED_MAX_ZOOM),
                "SEED_CONCURRENCY": str(Config.SEED_CONCURRENCY),
                "PURGE_CONCURRENCY": str(Config.PURGE_CONCURRENCY),
            },
            volumes={
                "/var/run/docker.sock": {"bind": "/var/run/docker.sock", "mode": "rw"},  # Allow Docker access
            },
            remove=False
            command=["bash", "-c", get_purge_and_seed_commands()]
        )

        logger.info(f"Docker job started successfully: {container.id}")
        return container.id

    except docker.errors.DockerException as e:
        logger.error(f"Error starting Docker job: {e}")
        return None
    