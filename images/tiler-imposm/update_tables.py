import os
import json
import logging
import subprocess
import time

# Logger configuration
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# Load DB configuration from environment variables
DB_CONFIG = {
    "dbname": os.getenv("POSTGRES_DB"),
    "user": os.getenv("POSTGRES_USER"),
    "password": os.getenv("POSTGRES_PASSWORD"),
    "host": os.getenv("POSTGRES_HOST"),
    "port": int(os.getenv("POSTGRES_PORT", 5432))
}

REQUIRED_ENV_VARS = ["POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_HOST"]
for var in REQUIRED_ENV_VARS:
    if not os.getenv(var):
        logger.error(f"The environment variable {var} is not defined. Exiting.")
        raise EnvironmentError(f"The environment variable {var} is not defined.")

PSQL_CONN = f"postgresql://{DB_CONFIG['user']}:{DB_CONFIG['password']}@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['dbname']}"

def load_imposm_config(filepath: str) -> dict:
    """
    Load the configuration from a JSON file.
    """
    logger.info(f"Loading configuration from {filepath}")
    with open(filepath, "r") as f:
        return json.load(f)

def execute_psql_query(query: str):
    """
    Execute an SQL query using psql.
    """
    try:
        result = subprocess.run(
            ["psql", PSQL_CONN, "-c", query],
            text=True,
            capture_output=True
        )
        if result.returncode != 0:
            logger.error(f"Error executing the query: {result.stderr.strip()}")
        else:
            logger.info(f"Query executed successfully:\n{result.stdout.strip()}")
    except Exception as e:
        logger.error(f"Error executing the query with psql: {e}")

def delete_sub_tables(generalized_tables: dict):
    """
    Deletes all sub-tables defined in the configuration.
    """
    logger.info("Starting deletion of sub-tables...")
    for table_name, table_info in generalized_tables.items():
        fixed_table_name = f"osm_{table_name}"
        sub_tables = table_info.get("sub_tables")

        # If no sub-tables are defined, skip
        if not sub_tables:
            logger.info(f"No sub-tables defined for {fixed_table_name}. Skipping.")
            continue

        for sub_table in sub_tables:
            sub_table_name = sub_table.get("table")
            if not sub_table_name:
                logger.warning(
                    f"Sub-table for {fixed_table_name} does not have a defined name. Skipping."
                )
                continue

            sub_fixed_table_name = f"osm_{sub_table_name}"

            # Check if the table exists before attempting to delete it
            if table_exists(sub_fixed_table_name):
                logger.info(f"Deleting sub-table {sub_fixed_table_name}...")
                drop_table_query = f"DROP TABLE IF EXISTS {sub_fixed_table_name} CASCADE;"
                execute_psql_query(drop_table_query)
            else:
                logger.info(f"Sub-table {sub_fixed_table_name} does not exist. Skipping.")

    logger.info("Sub-table deletion process completed.")


def table_exists(table_name: str) -> bool:
    """
    Checks if a table exists in the database.
    """
    query = f"SELECT to_regclass('public.{table_name}');"
    result = subprocess.run(
        ["psql", PSQL_CONN, "-t", "-c", query],
        text=True,
        capture_output=True
    )
    output = result.stdout.strip()
    return output != "" and output != "-"


def create_trigger_for_sub_table(sub_table_name: str, geometry_transform: str, sql_filter: str = None):
    """
    Creates triggers for a sub-table, applying the geometric transformation
    and optionally a SQL filter for future INSERT/UPDATE operations.
    Handles row deletions.
    If triggers already exist, they are dropped and recreated.
    """
    fixed_table_name = f"osm_{sub_table_name}"
    insert_update_trigger_name = f"{fixed_table_name}_before_insert_update"
    delete_trigger_name = f"{fixed_table_name}_before_delete"

    # Drop existing triggers if they exist
    drop_trigger_query = f"""
    DO $$
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM pg_trigger
            WHERE tgname = '{insert_update_trigger_name}'
        ) THEN
            EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I;', '{insert_update_trigger_name}', '{fixed_table_name}');
        END IF;

        IF EXISTS (
            SELECT 1
            FROM pg_trigger
            WHERE tgname = '{delete_trigger_name}'
        ) THEN
            EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I;', '{delete_trigger_name}', '{fixed_table_name}');
        END IF;
    END $$;
    """
    execute_psql_query(drop_trigger_query)
    logger.info(f"Existing triggers removed on table {fixed_table_name} (if they existed).")

    # Prepare the SQL filter clause if provided
    sql_filter_clause = f"({sql_filter})" if sql_filter else "TRUE"

    # Create the trigger for INSERT and UPDATE
    transform_for_trigger = geometry_transform.replace('geometry', 'NEW.geometry')

    insert_update_trigger_function = f"""
    CREATE OR REPLACE FUNCTION {fixed_table_name}_transform_trigger()
    RETURNS TRIGGER AS $$
    BEGIN
        -- Apply geometric transformation
        NEW.geometry = {transform_for_trigger};

        -- Apply optional SQL filter
        IF {sql_filter_clause} THEN
            RETURN NEW;
        ELSE
            RETURN NULL; -- Ignore the row if it doesn't match the filter
        END IF;
    END;
    $$ LANGUAGE plpgsql;

    CREATE TRIGGER {insert_update_trigger_name}
    BEFORE INSERT OR UPDATE ON {fixed_table_name}
    FOR EACH ROW
    EXECUTE FUNCTION {fixed_table_name}_transform_trigger();
    """
    execute_psql_query(insert_update_trigger_function)
    logger.info(f"Trigger {insert_update_trigger_name} created for INSERT/UPDATE on table {fixed_table_name}.")

    # Create the trigger for DELETE
    delete_trigger_function = f"""
    CREATE OR REPLACE FUNCTION {fixed_table_name}_delete_trigger()
    RETURNS TRIGGER AS $$
    BEGIN
        -- Log information about the deleted row
        RAISE NOTICE 'Row deleted from table % with osm_id: %', TG_TABLE_NAME, OLD.osm_id;
        RETURN OLD;
    END;
    $$ LANGUAGE plpgsql;

    CREATE TRIGGER {delete_trigger_name}
    BEFORE DELETE ON {fixed_table_name}
    FOR EACH ROW
    EXECUTE FUNCTION {fixed_table_name}_delete_trigger();
    """
    execute_psql_query(delete_trigger_function)
    logger.info(f"Trigger {delete_trigger_name} created for DELETE on table {fixed_table_name}.")
    

def apply_geometry_transformations(generalized_tables: dict):
    """
    Applies initial geometric transformations to generalized tables
    and creates sub-tables with their transformations and triggers.
    """
    logger.info("Starting initial geometric transformations...")
    for table_name, table_info in generalized_tables.items():
        fixed_table_name = f"osm_{table_name}"
        sub_tables = table_info.get("sub_tables")

        # Skip if no sub-tables are defined
        if not sub_tables:
            logger.info(f"No sub_tables defined for {fixed_table_name}. Skipping.")
            continue

        for sub_table in sub_tables:
            sub_table_name = sub_table.get("table")
            if not sub_table_name:
                logger.warning(f"Sub-table for {fixed_table_name} has no defined name. Skipping.")
                continue

            sub_table_fixed_name = f"osm_{sub_table_name}"
            sub_geometry_transform = sub_table["geometry_transform"]
            sub_sql_filter = sub_table.get("sql_filter", None)

            # Retrieve the list of columns from the main table
            get_columns_query = f"""
            SELECT column_name 
            FROM information_schema.columns
            WHERE table_schema = 'public'
            AND table_name = '{fixed_table_name}'
            ORDER BY ordinal_position;
            """
            result = subprocess.run(
                ["psql", PSQL_CONN, "-t", "-c", get_columns_query],
                text=True,
                capture_output=True
            )
            if result.returncode != 0:
                logger.error(f"Error retrieving columns for {fixed_table_name}: {result.stderr.strip()}")
                continue

            # Clean and retrieve the list of columns
            retrieved_columns = [col.strip() for col in result.stdout.strip().split('\n') if col.strip()]

            if not retrieved_columns:
                logger.warning(f"No columns found for {fixed_table_name}. Skipping.")
                continue

            # Create the sub-table if it doesn't exist
            if not table_exists(sub_table_fixed_name):
                logger.info(f"Creating sub-table {sub_table_fixed_name} based on {fixed_table_name}...")
                create_table_query = f"""
                CREATE TABLE {sub_table_fixed_name} (LIKE {fixed_table_name} INCLUDING ALL);
                """
                execute_psql_query(create_table_query)

                # Build the column list for SELECT, replacing geometry with geometry_transform
                selected_columns = []
                for col in retrieved_columns:
                    if col == 'geometry':
                        selected_columns.append(f"{sub_geometry_transform} AS geometry")
                    else:
                        selected_columns.append(col)

                # Generate the INSERT query with optional SQL filter
                where_clause = f"WHERE {sub_sql_filter}" if sub_sql_filter else ""
                insert_query = f"""
                INSERT INTO {sub_table_fixed_name} ({", ".join(retrieved_columns)})
                SELECT {", ".join(selected_columns)}
                FROM {fixed_table_name}
                {where_clause};
                """
                execute_psql_query(insert_query)
            else:
                logger.info(f"Sub-table {sub_table_fixed_name} already exists. Skipping creation.")

            # Create triggers for the sub-table
            create_trigger_for_sub_table(sub_table_name, sub_geometry_transform, sub_sql_filter)

def main(imposm3_config_path: str):
    """
    Main flow:
    1. Load the configuration.
    2. Apply initial geometric transformations and create derived tables with their triggers.
    """
    try:
        config = load_imposm_config(imposm3_config_path)
        generalized_tables = config.get("generalized_tables", {})

        ## Delete tables
        delete_sub_tables(generalized_tables)

        # Apply initial transformations and create derived tables
        apply_geometry_transformations(generalized_tables)

        logger.info("Process completed successfully.")
    except Exception as e:
        logger.error(f"An error occurred during execution: {e}")
        raise

if __name__ == "__main__":
    imposm3_config_path = "config/imposm3.json"
    main(imposm3_config_path)