import os
import json
import logging
import psycopg2

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

# Database configuration
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

def get_column_data_type(cur, table_name, column_name):
    """Obtener el tipo de datos de una columna."""
    cur.execute(f"""
        SELECT data_type
        FROM information_schema.columns
        WHERE table_name = %s AND column_name = %s;
    """, (table_name, column_name))
    result = cur.fetchone()
    return result[0] if result else "TEXT"

def create_transform_table_and_trigger(conn, table_name, table_info):
    """Crear tabla de transformación y disparador dinámicamente."""
    transform_table_name = f"{table_name}_transform"
    print("================")
    print(transform_table_name)

    geometry_transform = table_info.get("geometry_transform")
    print(geometry_transform)

    if not geometry_transform:
        logger.warning(f"No se definió la transformación de geometría para {table_name}. Saltando.")
        return

    logger.info(f"Creando tabla de transformación y disparador para {table_name}...")

    with conn.cursor() as cur:
        # Obtener los nombres de las columnas dinámicamente
        cur.execute(f"SELECT column_name FROM information_schema.columns WHERE table_name = %s", (table_name,))
        columns = [row[0] for row in cur.fetchall()]

        if not columns:
            logger.error(f"La tabla {table_name} no tiene columnas. Saltando.")
            return

        if "geometry" not in columns:
            logger.error(f"La tabla {table_name} debe tener columnas 'geometry' y 'osm_id'. Saltando.")
            return

        # Excluir la columna de geometría para la transformación
        columns_without_geometry = [col for col in columns if col != "geometry"]
        columns_select = ", ".join(columns_without_geometry)

        # Crear la tabla de transformación vacía
        create_table_query = f"""
        CREATE TABLE IF NOT EXISTS {transform_table_name} AS 
        SELECT * FROM {table_name} WHERE FALSE;
        CREATE UNIQUE INDEX {transform_table_name}_pkey ON {transform_table_name}(osm_id int8_ops);
        CREATE INDEX {transform_table_name}_geom ON {transform_table_name} USING GIST (geometry gist_geometry_ops_2d);
        """

        cur.execute(create_table_query)
        conn.commit()
        logger.info(f"Tabla de transformación {transform_table_name} creada.")

        # Copiar los datos aplicando la transformación
        insert_data_query = f"""
        INSERT INTO {transform_table_name} (
            {columns_select}, geometry
        )
        SELECT 
            {columns_select}, {geometry_transform} AS geometry
        FROM {table_name};
        """
        cur.execute(insert_data_query)
        conn.commit()
        logger.info(f"Datos copiados a {transform_table_name} aplicando la transformación.")

        # Crear la función del disparador
        trigger_function_name = f"{table_name}_transform_trigger"
        trigger_function_query = f"""
        CREATE OR REPLACE FUNCTION {trigger_function_name}()
        RETURNS TRIGGER AS $$
        BEGIN
            -- Handle DELETE operation
            IF TG_OP = 'DELETE' THEN
                DELETE FROM {transform_table_name}
                WHERE osm_id = OLD.osm_id;
                RETURN OLD;
            END IF;

            -- Handle INSERT and UPDATE operations
            IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
                -- Check if the row exists in the transform table
                IF EXISTS (
                    SELECT 1 
                    FROM {transform_table_name} 
                    WHERE osm_id = NEW.osm_id
                ) THEN
                    -- If it exists, update the row
                    UPDATE {transform_table_name}
                    SET
                        {", ".join([f"{col} = NEW.{col}" for col in columns_without_geometry])},
                        geometry = {geometry_transform.replace('geometry', 'NEW.geometry')}
                    WHERE osm_id = NEW.osm_id;
                ELSE
                    -- If it does not exist, insert a new row
                    INSERT INTO {transform_table_name} (
                        {columns_select}, geometry
                    )
                    VALUES (
                        {", ".join([f"NEW.{col}" for col in columns_without_geometry])},
                        {geometry_transform.replace('geometry', 'NEW.geometry')}
                    );
                END IF;

                RETURN NEW;
            END IF;

            -- If no matching operation, raise an exception (optional for debugging)
            RAISE EXCEPTION 'Unexpected trigger operation: %', TG_OP;
        END;
        $$ LANGUAGE plpgsql;
        """
        print("================="*20)
        print(trigger_function_query)
        cur.execute(trigger_function_query)
        conn.commit()
        logger.info(f"Función del disparador {trigger_function_name} creada.")

        # Crear el disparador
        trigger_name = f"{table_name}_after_insert_update_delete"
        create_trigger_query = f"""
        CREATE TRIGGER {trigger_name}
        AFTER INSERT OR UPDATE OR DELETE ON {table_name}
        FOR EACH ROW
        EXECUTE FUNCTION {trigger_function_name}();
        """
        cur.execute(create_trigger_query)
        conn.commit()
        logger.info(f"Disparador {trigger_name} creado para la tabla {table_name}.")



def main(imposm3_config_path):
    """Main execution flow."""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        # Load the imposm3.json configuration
        config = load_imposm_config(imposm3_config_path)
        generalized_tables = config.get("generalized_tables", {})

        # Create transform tables and triggers
        for table_name, table_info in generalized_tables.items():
            table_name = f"osm_{table_name}"
            create_transform_table_and_trigger(conn, table_name, table_info)

        logger.info("All transform tables and triggers created successfully.")
    except Exception as e:
        logger.error(f"An error occurred during execution: {e}")
        raise
    finally:
        if conn:
            conn.close()


if __name__ == "__main__":
    imposm3_config_path = "./config/imposm3.json"
    main(imposm3_config_path)