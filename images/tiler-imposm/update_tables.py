import os
import json
import logging
import subprocess
import time

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

DB_CONFIG = {
    "dbname": os.getenv("POSTGRES_DB"),
    "user": os.getenv("POSTGRES_USER"),
    "password": os.getenv("POSTGRES_PASSWORD"),
    "host": os.getenv("POSTGRES_HOST"),
    "port": int(os.getenv("POSTGRES_PORT", 5432))
}

PSQL_CONN = f"postgresql://{DB_CONFIG['user']}:{DB_CONFIG['password']}@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['dbname']}"

REQUIRED_ENV_VARS = ["POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_HOST"]
for var in REQUIRED_ENV_VARS:
    if not os.getenv(var):
        logger.error(f"Environment variable {var} is not defined. Exiting.")
        raise EnvironmentError(f"Environment variable {var} is not defined.")

def load_imposm_config(filepath):
    """Load the imposm3.json configuration file."""
    logger.info(f"Loading configuration from {filepath}")
    try:
        with open(filepath, "r") as f:
            return json.load(f)
    except FileNotFoundError:
        logger.error(f"Configuration file {filepath} not found.")
        raise
    except json.JSONDecodeError:
        logger.error(f"Error parsing JSON from {filepath}.")
        raise

def execute_psql_query(query):
    """Execute a query using psql and print the output."""
    try:
        logger.info(f"Executing query:\t{query}")
        result = subprocess.run(
            ["psql", PSQL_CONN, "-c", query],
            text=True,
            capture_output=True
        )
        if result.returncode != 0:
            logger.error(f"Error executing query: {result.stderr}")
        else:
            logger.info(f"Query executed successfully:\n{result.stdout}")
    except Exception as e:
        logger.error(f"Error while executing query with psql: {e}")

def delete_existing_triggers(generalized_tables):
    """Delete existing triggers before applying transformations."""
    logger.info("Deleting existing triggers...")
    for table_name in generalized_tables.keys():
        fixed_table_name = f"osm_{table_name}"
        trigger_name = f"{fixed_table_name}_before_insert_update"

        drop_trigger_query = f"""
        DROP TRIGGER IF EXISTS {trigger_name} ON {fixed_table_name};
        DROP FUNCTION IF EXISTS {fixed_table_name}_transform_trigger();
        """
        execute_psql_query(drop_trigger_query)

def apply_geometry_transformations(generalized_tables):
    """Apply geometry transformations using psql."""
    logger.info("Starting geometry transformations...")
    for table_name, table_info in generalized_tables.items():
        fixed_table_name = f"osm_{table_name}"
        geometry_transform = table_info.get("geometry_transform")
        geometry_transform_types = table_info.get("geometry_transform_types")

        # Skip if transform or types are not defined
        if not geometry_transform or not geometry_transform_types:
            logger.warning(
                f"Skipping transformations for {fixed_table_name}: "
                "'geometry_transform' or 'geometry_transform_types' not defined."
            )
            continue

        # Build the SQL query
        sql_query = f"""UPDATE {fixed_table_name} SET geometry = {geometry_transform} WHERE {geometry_transform_types};"""
        start_time = time.time()
        execute_psql_query(sql_query)
        elapsed_time = time.time() - start_time

        logger.info(f"Transformation for table {fixed_table_name} completed in {elapsed_time:.2f} seconds.")

def create_triggers(generalized_tables):
    """Create triggers for future updates using psql."""
    logger.info("Creating triggers for future geometry transformations...")
    for table_name, table_info in generalized_tables.items():
        fixed_table_name = f"osm_{table_name}"
        geometry_transform = table_info.get("geometry_transform")
        geometry_transform_types = table_info.get("geometry_transform_types")

        # Skip if transform or types are not defined
        if not geometry_transform or not geometry_transform_types:
            logger.warning(
                f"Skipping trigger creation for {fixed_table_name}: "
                "'geometry_transform' or 'geometry_transform_types' not defined."
            )
            continue

        # Create the trigger function SQL
        trigger_function = f"""
        CREATE OR REPLACE FUNCTION {fixed_table_name}_transform_trigger()
        RETURNS TRIGGER AS $$
        BEGIN
            IF {geometry_transform_types} THEN
                NEW.geometry = {geometry_transform};
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """
        execute_psql_query(trigger_function)

        # Create the trigger SQL
        trigger = f"""
        CREATE TRIGGER {fixed_table_name}_before_insert_update
        BEFORE INSERT OR UPDATE ON {fixed_table_name}
        FOR EACH ROW
        EXECUTE FUNCTION {fixed_table_name}_transform_trigger();
        """
        execute_psql_query(trigger)

def main(imposm3_config_path):
    """Main execution flow."""
    try:
        # Load the imposm3.json configuration
        config = load_imposm_config(imposm3_config_path)
        generalized_tables = config.get("generalized_tables", {})

        # Delete existing triggers
        logger.info("Deleting existing triggers...")
        delete_existing_triggers(generalized_tables)

        # Apply initial geometry transformations
        logger.info("Starting initial geometry transformations...")
        apply_geometry_transformations(generalized_tables)

        # Recreate triggers for future transformations
        logger.info("Recreating triggers for future updates...")
        create_triggers(generalized_tables)

        logger.info("All transformations and triggers completed successfully.")
    except Exception as e:
        logger.error(f"An error occurred during execution: {e}")
        raise

if __name__ == "__main__":
    imposm3_config_path = "config/imposm3.json"
    main(imposm3_config_path)
    