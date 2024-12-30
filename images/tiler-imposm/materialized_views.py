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
    "port": int(os.getenv("POSTGRES_PORT", 5432)),
}

REQUIRED_ENV_VARS = ["POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_HOST"]
for var in REQUIRED_ENV_VARS:
    if not os.getenv(var):
        logger.error(f"The environment variable {var} is not defined. Exiting.")
        raise EnvironmentError(f"The environment variable {var} is not defined.")

PSQL_CONN = f"postgresql://{DB_CONFIG['user']}:{DB_CONFIG['password']}@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['dbname']}"

REFRESH_MATERIALIZED_VIEWS_TIME= int(os.getenv("REFRESH_MATERIALIZED_VIEWS_TIME", 300))
# ------------------------------------------------------------------------------
#  HELPER FUNCTIONS
# ------------------------------------------------------------------------------
def execute_psql_query(query: str):
    """
    Executes an SQL query using the psql command-line tool.
    """
    try:
        result = subprocess.run(["psql", PSQL_CONN, "-c", query], text=True, capture_output=True)
        if result.returncode != 0:
            logger.error(f"Error executing the query: {result.stderr.strip()}")
        else:
            logger.info(f"Query executed successfully:\n{result.stdout.strip()}")
    except Exception as e:
        logger.error(f"Error executing the query with psql: {e}")


def object_exists(object_name: str) -> bool:
    """
    Checks if a table or materialized view exists in the public schema.
    """
    query = f"SELECT to_regclass('public.{object_name}');"
    result = subprocess.run(["psql", PSQL_CONN, "-t", "-c", query], text=True, capture_output=True)
    output = result.stdout.strip()
    return output not in ("", "-")


def get_columns_of_table(table_name: str) -> list:
    """
    Returns a list of columns for the given table in the 'public' schema.
    """
    query = f"""
        SELECT column_name 
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = '{table_name}'
        ORDER BY ordinal_position;
    """
    result = subprocess.run(["psql", PSQL_CONN, "-t", "-c", query], text=True, capture_output=True)
    if result.returncode != 0:
        logger.error(f"Error retrieving columns for {table_name}: {result.stderr.strip()}")
        return []

    columns = [col.strip() for col in result.stdout.strip().split("\n") if col.strip()]
    return columns


def create_indexes_for_mview(mview_name: str, columns: list):
    """
    Creates indexes for 'osm_id' (B-Tree) and 'geometry' (GiST) in the specified materialized view,
    only if those columns exist.
    """
    # Check if the columns exist
    if "osm_id" in columns:
        create_idx_osm = f"CREATE INDEX idx_{mview_name}_osm_id ON {mview_name} (osm_id);"
        logger.info(f"Creating index for osm_id in {mview_name}")
        execute_psql_query(create_idx_osm)

    if "geometry" in columns:
        create_idx_geom = (
            f"CREATE INDEX idx_{mview_name}_geom ON {mview_name} USING GIST (geometry);"
        )
        logger.info(f"Creating index for geometry in {mview_name}")
        execute_psql_query(create_idx_geom)


def create_materialized_view(
    mview_name: str,
    base_table: str,
    columns: list,
    geometry_transform: str,
    sql_filter: str,
    force_recreate: bool = True,
):
    """
    Creates or recreates a materialized view with the given definition.
    """
    # Build the SELECT clause by replacing 'geometry' in the column list
    transformed_cols = []
    for col in columns:
        if col == "geometry":
            transformed_cols.append(f"{geometry_transform} AS geometry")
        else:
            transformed_cols.append(col)

    select_clause = ", ".join(transformed_cols)
    where_clause = f"WHERE {sql_filter}" if sql_filter else ""

    drop_query = f"DROP MATERIALIZED VIEW IF EXISTS {mview_name} CASCADE;"
    create_query = f"""
    CREATE MATERIALIZED VIEW {mview_name} AS
    SELECT {select_clause}
    FROM {base_table}
    {where_clause};
    """

    # If the view already exists and force_recreate=True, drop and recreate it
    if object_exists(mview_name):
        if force_recreate:
            logger.info(f"[force_recreate] Dropping existing materialized view: {mview_name}")
            execute_psql_query(drop_query)
            logger.info(f"Creating materialized view: {mview_name}")
            logger.info(f"{create_query}")
            execute_psql_query(create_query)
            create_indexes_for_mview(mview_name, columns)
        else:
            logger.info(
                f"Materialized view {mview_name} already exists and force_recreate=False. Skipping CREATE."
            )
    else:
        logger.info(f"Materialized view {mview_name} does not exist. Creating it...")
        execute_psql_query(create_query)
        create_indexes_for_mview(mview_name, columns)


# ------------------------------------------------------------------------------
#  CREATION/UPDATE OF VIEWS FROM LOADED CONFIG (NO RELOADING THE JSON)
# ------------------------------------------------------------------------------
def apply_materialized_views(config_dict: dict, force_recreate: bool = True):
    """
    Creates/Recreates the materialized views defined in 'generalized_tables',
    using the config already loaded into a dictionary (without reloading the JSON).
    """
    generalized_tables = config_dict.get("generalized_tables", {})
    if not generalized_tables:
        logger.warning("No 'generalized_tables' found in config. Skipping creation of matviews.")
        return

    for gtable_name, gtable_info in generalized_tables.items():

        imposm_base_table = f"osm_{gtable_name}"
        logger.info("-" * 80)
        logger.info(f"Imposm base table name: {imposm_base_table}")

        materialized_views = gtable_info.get("materialized_views", [])
        if not materialized_views:
            logger.info(f"No views defined for {gtable_name}. Skipping.")
            continue

        columns = get_columns_of_table(imposm_base_table)
        if not columns:
            logger.warning(f"No columns found for {imposm_base_table}. Skipping.")
            continue

        for mt_view in materialized_views:
            mview_name = "osm_" + mt_view.get("view")
            geometry_transform = mt_view.get("geometry_transform", "geometry")
            sql_filter = mt_view.get("sql_filter", "")
            logger.info("-" * 40)
            logger.info(f"Processing view {mview_name} | {geometry_transform} | {sql_filter}")

            logger.info(f"  -> Creating/Updating materialized view: {mview_name}")

            create_materialized_view(
                mview_name=mview_name,
                base_table=imposm_base_table,
                columns=columns,
                geometry_transform=geometry_transform,
                sql_filter=sql_filter,
                force_recreate=force_recreate,
            )


# ------------------------------------------------------------------------------
#  REFRESH OF ALL VIEWS
# ------------------------------------------------------------------------------
def refresh_all_materialized_views(config_dict: dict):
    """
    Refreshes all matviews listed under 'generalized_tables' -> 'materialized_views',
    without reloading the config file.
    """
    generalized_tables = config_dict.get("generalized_tables", {})
    for gtable_name, gtable_info in generalized_tables.items():
        materialized_views = gtable_info.get("materialized_views", [])
        for mt_view in materialized_views:
            if not mt_view:
                continue
            mview_name = "osm_" + mt_view.get("view")
            if object_exists(mview_name):
                logger.info(f"Refreshing materialized view: {mview_name}")
                query = f"REFRESH MATERIALIZED VIEW {mview_name};"
                execute_psql_query(query)
            else:
                logger.warning(f"Materialized view {mview_name} not found. Skipping refresh.")


# ------------------------------------------------------------------------------
#  MAIN: LOADS CONFIG ONCE, CREATES/UPDATES VIEWS, THEN REFRESHES THEM IN A LOOP
# ------------------------------------------------------------------------------
def main():
    config_path = "config/imposm3.json"

    # 1) Load the config
    logger.info(f"Loading configuration from: {config_path}")
    with open(config_path, "r") as f:
        config_dict = json.load(f)

    # 2) (Optional) Create/Recreate the views just once at startup.
    #    Set 'force_recreate=False' in production if you don't want
    #    to drop and recreate the view every time the script starts.
    apply_materialized_views(config_dict, force_recreate=True)

    # 3) Infinite loop to refresh
    while True:
        logger.info("Refreshing all materialized views...")
        refresh_all_materialized_views(config_dict)
        logger.info("All materialized views refreshed. Sleeping 60 seconds...")
        time.sleep(REFRESH_MATERIALIZED_VIEWS_TIME)


if __name__ == "__main__":
    main()
