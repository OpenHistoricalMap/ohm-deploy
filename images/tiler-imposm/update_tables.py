import os
import json
import psycopg2
from psycopg2 import sql
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

DB_CONFIG = {
    "dbname": os.getenv("POSTGRES_DB"),
    "user": os.getenv("POSTGRES_USER"),
    "password": os.getenv("POSTGRES_PASSWORD"),
    "host": os.getenv("POSTGRES_HOST"),
    "port": int(os.getenv("POSTGRES_PORT", 5432))
}

# Verify that all required environment variables are defined
REQUIRED_ENV_VARS = ["POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_HOST"]
for var in REQUIRED_ENV_VARS:
    if not os.getenv(var):
        logger.error(f"Environment variable {var} is not defined. Exiting.")
        raise EnvironmentError(f"Environment variable {var} is not defined.")

def load_imposm_config(filepath):
    """Load the imposm3.json configuration file"""
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

def apply_geometry_transformations(conn, generalized_tables):
    """Apply geometry transformations to the specified tables"""
    logger.info("Starting geometry transformations...")
    with conn.cursor() as cur:
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

            # Execute transformation query
            sql_query = sql.SQL("""
            UPDATE {table}
            SET geometry = {transform}
            WHERE {types_condition};
            """).format(
                table=sql.Identifier(fixed_table_name),
                transform=sql.SQL(geometry_transform),
                types_condition=sql.SQL(geometry_transform_types)
            )
            try:
                logger.info(f"Applying transformation '{geometry_transform}' to table {fixed_table_name}")
                cur.execute(sql_query)
                logger.info(f"Transformation completed successfully for {fixed_table_name}")
            except Exception as e:
                logger.error(f"Error applying transformation to {fixed_table_name}: {e}")
        conn.commit()

def create_triggers(conn, generalized_tables):
    """Create triggers for future inserts/updates"""
    logger.info("Creating triggers for future geometry transformations...")
    with conn.cursor() as cur:
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

            # Create trigger function
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
            try:
                logger.info(f"Creating trigger function for {fixed_table_name}")
                cur.execute(trigger_function)

                # Create the trigger
                trigger = f"""
                CREATE TRIGGER {fixed_table_name}_before_insert_update
                BEFORE INSERT OR UPDATE ON {fixed_table_name}
                FOR EACH ROW
                EXECUTE FUNCTION {fixed_table_name}_transform_trigger();
                """
                cur.execute(trigger)
                logger.info(f"Trigger created successfully for {fixed_table_name}")
            except Exception as e:
                logger.error(f"Error creating trigger for {fixed_table_name}: {e}")
        conn.commit()

def main(imposm3_config_path):
    logger.info("Connecting to the PostgreSQL database...")
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        logger.info("Connection established successfully.")
    except Exception as e:
        logger.error(f"Error connecting to the database: {e}")
        raise

    try:
        # Load the imposm3.json configuration
        config = load_imposm_config(imposm3_config_path)
        generalized_tables = config.get("generalized_tables", {})

        # Apply initial geometry transformations
        logger.info("Starting initial geometry transformations...")
        apply_geometry_transformations(conn, generalized_tables)

        # Create triggers for future transformations
        logger.info("Setting up triggers for future updates...")
        create_triggers(conn, generalized_tables)

        logger.info("All transformations and triggers completed successfully.")
    except Exception as e:
        logger.error(f"An error occurred during execution: {e}")
        raise
    finally:
        conn.close()
        logger.info("Database connection closed.")

if __name__ == "__main__":
    imposm3_config_path = "config/imposm3.json"
    main(imposm3_config_path)
