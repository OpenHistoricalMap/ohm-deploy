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

def create_trigger_for_imposm_table(
    imposm_fixed_table_name: str,
    sub_table_name: str,
    retrieved_columns: list,
    geometry_transform: str,
    sql_filter: str = None
):
    """
    Creates a single trigger (AFTER INSERT OR UPDATE OR DELETE) on the main table
    (imposm_fixed_table_name) so that any insertion, update, or deletion on the main table
    is automatically replicated to the sub-table (osm_sub_table_name), applying the geometric
    transformation (geometry_transform), the SQL filter (sql_filter), and replicating the columns
    specified in retrieved_columns.
    """

    # Actual name of the sub-table in your schema
    osm_sub_table_name = f"osm_{sub_table_name}"

    # Names for the function and the trigger
    function_name = f"{imposm_fixed_table_name}_replicate_{sub_table_name}_fn"
    trigger_name = f"{imposm_fixed_table_name}_replicate_{sub_table_name}_trigger"

    # 1) Remove the trigger if it exists
    drop_trigger_query = f"""
    DO $$
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM pg_trigger
            WHERE tgname = '{trigger_name}'
        ) THEN
            EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I;', '{trigger_name}', '{imposm_fixed_table_name}');
        END IF;
    END $$;
    """
    # Optionally execute or comment out if you don't want to always drop the existing trigger
    execute_psql_query(drop_trigger_query)
    logger.info(f"Trigger {trigger_name} removed from {imposm_fixed_table_name} (if it existed).")

    # 2) Build the list of columns and the SELECT part for the INSERT into the sub-table
    transformed_columns = []
    upsert_update_assignments = []

    for col in retrieved_columns:
        if col == "geometry":
            # Transformation during INSERT
            geom_expr_insert = geometry_transform.replace("geometry", "NEW.geometry")
            # Transformation during UPDATE (EXCLUDED is the row that caused the conflict)
            geom_expr_update = geometry_transform.replace("geometry", "EXCLUDED.geometry")

            transformed_columns.append(f"{geom_expr_insert} AS {col}")
            upsert_update_assignments.append(f"{col} = {geom_expr_update}")
        else:
            transformed_columns.append(f"NEW.{col}")
            upsert_update_assignments.append(f"{col} = EXCLUDED.{col}")

    columns_str = ", ".join(retrieved_columns)
    values_str = ", ".join(transformed_columns)
    on_conflict_update_str = ", ".join(upsert_update_assignments)

    # 3) Prepare the filter clause; if it does not exist, it will simply be TRUE
    if sql_filter is not None:
        # Replace "name" with "NEW.name" (or other columns, if needed)
        modified_sql_filter = sql_filter.replace("name", "NEW.name")
        # You can also handle multiple columns or do more replacements if required
        sql_filter_clause = f"({modified_sql_filter})"
    else:
        # If no filter is provided, default to a condition that always passes
        sql_filter_clause = "TRUE"

    # 4) Create the plpgsql function with additional logging via RAISE
    replicate_function = f"""
    CREATE OR REPLACE FUNCTION {function_name}()
    RETURNS TRIGGER AS $$
    BEGIN
        -- Log basic info whenever the trigger function is invoked
        RAISE NOTICE 'Trigger function invoked on table % for operation %', TG_RELNAME, TG_OP;

        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            -- Log osm_id (if it exists) before filter check
            RAISE NOTICE 'Processing row with osm_id: %', NEW.osm_id;

            IF {sql_filter_clause} THEN
                RAISE NOTICE 'Row meets filter condition. Performing UPSERT for osm_id: %', NEW.osm_id;

                INSERT INTO {osm_sub_table_name} ({columns_str})
                SELECT {values_str}
                ON CONFLICT (osm_id)
                DO UPDATE
                    SET {on_conflict_update_str};
            END IF;

            RETURN NEW;

        ELSIF (TG_OP = 'DELETE') THEN
            RAISE NOTICE 'Deleting row osm_id: % from sub-table.', OLD.osm_id;

            DELETE FROM {osm_sub_table_name}
            WHERE osm_id = OLD.osm_id;

            RETURN OLD;
        END IF;

        RETURN NULL;  -- Safety return
    END;
    $$ LANGUAGE plpgsql;
    """
    # Create the function
    # print(replicate_function)
    execute_psql_query(replicate_function)
    logger.info(f"Function {function_name} created to replicate data from {imposm_fixed_table_name} to {osm_sub_table_name}.")

    # 5) Create the trigger that calls this function AFTER INSERT, UPDATE, DELETE
    replicate_trigger = f"""
    CREATE TRIGGER {trigger_name}
    AFTER INSERT OR UPDATE OR DELETE
    ON {imposm_fixed_table_name}
    FOR EACH ROW
    EXECUTE FUNCTION {function_name}();
    """
    # Create the trigger
    execute_psql_query(replicate_trigger)
    logger.info(f"Trigger {trigger_name} created on {imposm_fixed_table_name} to replicate to {osm_sub_table_name}.")

def apply_geometry_transformations(generalized_tables: dict):
    """
    Applies initial geometric transformations to generalized tables
    and creates sub-tables with their transformations and triggers.
    """
    logger.info("Starting initial geometric transformations...")
    for table_name, table_info in generalized_tables.items():
        imposm_fixed_table_name = f"osm_{table_name}"
        sub_tables = table_info.get("sub_tables")

        # Skip if no sub-tables are defined
        if not sub_tables:
            logger.info(f"No sub_tables defined for {imposm_fixed_table_name}. Skipping.")
            continue

        for sub_table in sub_tables:
            sub_table_name = sub_table.get("table")
            if not sub_table_name:
                logger.warning(f"Sub-table for {imposm_fixed_table_name} has no defined name. Skipping.")
                continue

            sub_table_fixed_name = f"osm_{sub_table_name}"
            sub_geometry_transform = sub_table["geometry_transform"]
            sub_sql_filter = sub_table.get("sql_filter", None)

            # Retrieve the list of columns from the main table
            get_columns_query = f"""
            SELECT column_name 
            FROM information_schema.columns
            WHERE table_schema = 'public'
            AND table_name = '{imposm_fixed_table_name}'
            ORDER BY ordinal_position;
            """
            result = subprocess.run(
                ["psql", PSQL_CONN, "-t", "-c", get_columns_query],
                text=True,
                capture_output=True
            )
            if result.returncode != 0:
                logger.error(f"Error retrieving columns for {imposm_fixed_table_name}: {result.stderr.strip()}")
                continue

            # Clean and retrieve the list of columns
            retrieved_columns = [col.strip() for col in result.stdout.strip().split('\n') if col.strip()]

            if not retrieved_columns:
                logger.warning(f"No columns found for {imposm_fixed_table_name}. Skipping.")
                continue

            # Create the sub-table if it doesn't exist
            if not table_exists(sub_table_fixed_name):
                logger.info(f"Creating sub-table {sub_table_fixed_name} based on {imposm_fixed_table_name}...")
                create_table_query = f"""
                CREATE TABLE {sub_table_fixed_name} (LIKE {imposm_fixed_table_name} INCLUDING ALL);
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
                FROM {imposm_fixed_table_name}
                {where_clause};
                """
                execute_psql_query(insert_query)
            else:
                logger.info(f"Sub-table {sub_table_fixed_name} already exists. Skipping creation.")

            # Create triggers for the sub-table
            create_trigger_for_imposm_table(
                imposm_fixed_table_name,
                sub_table_name,
                retrieved_columns,
                sub_geometry_transform,
                sub_sql_filter
            )

def main(imposm3_config_path: str):
    """
    Main flow:
    1. Load the configuration.
    2. Apply initial geometric transformations and create derived tables with their triggers.
    """
    try:
        config = load_imposm_config(imposm3_config_path)
        generalized_tables = config.get("generalized_tables", {})

        # Uncomment below if you want to delete existing sub-tables first
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
