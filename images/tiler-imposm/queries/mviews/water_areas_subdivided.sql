-- ============================================================================
-- Function: create_or_refresh_water_areas_subdivided_mview
-- Description:
--   This script creates materialized views for water areas using the 
--   ST_Subdivide function to reduce the complexity of certain geometries.
--   It includes multilingual columns dynamically loaded from the `languages` table.
--
-- Parameters:
--   input_table  TEXT  - The source table containing raw geometries.
--   mview_name   TEXT  - The name of the materialized view to be created.
--   force_create BOOLEAN - If TRUE, forces recreation regardless of hash change.
-- ============================================================================

DROP FUNCTION IF EXISTS create_or_refresh_water_areas_subdivided_mview;
CREATE OR REPLACE FUNCTION create_or_refresh_water_areas_subdivided_mview(
  input_table TEXT,
  mview_name TEXT,
  force_create BOOLEAN DEFAULT FALSE
)
RETURNS void AS $$
DECLARE
    lang_columns TEXT;
BEGIN
    -- Check if we should recreate or refresh the view
    IF NOT force_create AND NOT recreate_or_refresh_view(mview_name) THEN
        RETURN;
    END IF;

    RAISE NOTICE 'Creating subdivided materialized view from % to %', input_table, mview_name;

    -- Get dynamic language columns from `languages` table
    lang_columns := get_language_columns();

    -- Drop existing materialized view if it exists
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I;', mview_name);

    -- Create the materialized view with subdivided and valid geometries
    EXECUTE format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
          row_number() OVER () AS id,
          geometry,
          osm_id,
          name,
          type,
          start_date,
          end_date,
          area,
          tags,
          %s
        FROM (
          SELECT
            ST_Subdivide((g).geom, 512) AS geometry,
            osm_id,
            name,
            type,
            start_date,
            end_date,
            area,
            tags,
            %s
          FROM (
            SELECT 
              osm_id,
              name,
              type,
              start_date,
              end_date,
              tags,
              area,
              ST_Dump(ST_MakeValid(geometry)) AS g,
              %s
            FROM %I
            WHERE geometry IS NOT NULL
          ) AS fixed_geoms
          WHERE GeometryType((g).geom) IN ('POLYGON', 'MULTIPOLYGON')
        ) AS final_data;
    $sql$, mview_name, lang_columns, lang_columns, lang_columns, input_table);

    -- Create unique index
    EXECUTE format('CREATE UNIQUE INDEX idx_%I_unique ON %I(id);', mview_name, mview_name);

    -- Create geometry index
    EXECUTE format('CREATE INDEX idx_%I_geom ON %I USING GIST (geometry);', mview_name, mview_name);
END;
$$ LANGUAGE plpgsql;

-- Create the materialized views for each zoom level
SELECT create_or_refresh_water_areas_subdivided_mview('osm_water_areas_z0_2', 'mv_water_areas_z0_2_subdivided');
SELECT create_or_refresh_water_areas_subdivided_mview('osm_water_areas_z3_5', 'mv_water_areas_z3_5_subdivided');
SELECT create_or_refresh_water_areas_subdivided_mview('osm_water_areas_z6_7', 'mv_water_areas_z6_7_subdivided');
SELECT create_or_refresh_water_areas_subdivided_mview('osm_water_areas_z8_9', 'mv_water_areas_z8_9_subdivided');

-- We are giong to use same water tables for zoom>9, osm_water_areas_z10_12, osm_water_areas_z13_15 and osm_water_areas
