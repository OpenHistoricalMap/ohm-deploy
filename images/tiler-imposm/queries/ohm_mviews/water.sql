-- ============================================================================
-- Function: create_water_areas_subdivided_mview
-- Description:
--   This script creates materialized views for water areas using the 
--   ST_Subdivide function to reduce the complexity of certain geometries.
--   It includes multilingual columns dynamically loaded from the `languages` table.
--
-- Parameters:
--   input_table  TEXT  - The source table containing raw geometries.
--   mview_name   TEXT  - The name of the materialized view to be created.
-- ============================================================================

DROP FUNCTION IF EXISTS create_water_areas_subdivided_mview;
CREATE OR REPLACE FUNCTION create_water_areas_subdivided_mview(
  input_table TEXT,
  mview_name TEXT
)
RETURNS void AS $$
DECLARE
    lang_columns TEXT;
    sql_create TEXT;
BEGIN
    RAISE NOTICE 'Creating subdivided materialized view from % to %', input_table, mview_name;

    -- Get dynamic language columns from `languages` table
    lang_columns := get_language_columns();

    -- Drop existing materialized view if it exists
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I;', mview_name);

    -- Create the materialized view with subdivided and valid geometries
    sql_create :=  format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
          row_number() OVER () AS id,
          geometry,
          osm_id,
          NULLIF(name, '') AS name,
          NULLIF(type, '') AS type,
          NULLIF(start_date, '') AS start_date,
          NULLIF(end_date, '') AS end_date,
          isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
          isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
          area,
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
              area,
              ST_Dump(ST_MakeValid(geometry)) AS g,
              tags,
              %s
            FROM %I
            WHERE geometry IS NOT NULL
          ) AS fixed_geoms
          WHERE GeometryType((g).geom) IN ('POLYGON', 'MULTIPOLYGON')
        ) AS final_data;
    $sql$, mview_name, lang_columns, lang_columns, lang_columns, input_table);

    EXECUTE sql_create;

    -- Create indexes
    EXECUTE format('CREATE UNIQUE INDEX idx_%I_unique ON %I(id);', mview_name, mview_name);
    EXECUTE format('CREATE INDEX idx_%I_geom ON %I USING GIST (geometry);', mview_name, mview_name);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Function: create_water_areas_centroids_mview
-- Description:
--   This function creates a materialized view with centroids for named water areas.
--   It uses ST_MaximumInscribedCircle to compute a representative centroid from
--   each polygonal feature. The function can be called per zoom level using different source tables.
--
-- Parameters:
--   source_table TEXT - Source table containing water area polygons.
--   view_name    TEXT - Name of the resulting materialized view.
--
-- Notes:
--   - Only features with non-empty names are included.
--   - Geometry is computed as the center of the maximum inscribed circle.
--   - A GiST index is created on geometry, and uniqueness is enforced on osm_id.
-- ============================================================================

DROP FUNCTION IF EXISTS create_water_areas_centroids_mview;
CREATE OR REPLACE FUNCTION create_water_areas_centroids_mview(
    source_table TEXT,
    view_name TEXT
)
RETURNS void AS $$
DECLARE 
    sql_drop TEXT;
    sql_create TEXT;
    sql_index TEXT;
    sql_unique_index TEXT;
    lang_columns TEXT;
BEGIN
    RAISE NOTICE 'Creating centroid materialized view from % to %', source_table, view_name;

    -- Get dynamic language columns from `languages` table
    lang_columns := get_language_columns();

    -- Drop existing materialized view
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);

    RAISE NOTICE 'Dropped materialized view: %', view_name;

    -- Create the materialized view with centroid geometry
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            osm_id,
            NULLIF(name, '') AS name,
            NULLIF(type, '') AS type,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
            area,
            %s,
            (ST_MaximumInscribedCircle(geometry)).center AS geometry
        FROM %I
        WHERE name IS NOT NULL AND name <> '';
    $sql$, view_name, lang_columns, source_table);

    EXECUTE sql_create;

    -- Create indexs
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_osm_id ON %I (osm_id);', view_name, view_name);

END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Create materialized views for water ceontroids
-- ============================================================================
SELECT create_water_areas_centroids_mview('osm_water_areas_z0_2', 'mv_water_areas_centroids_z0_2');
SELECT create_water_areas_centroids_mview('osm_water_areas_z3_5', 'mv_water_areas_centroids_z3_5');
SELECT create_water_areas_centroids_mview('osm_water_areas_z6_7', 'mv_water_areas_centroids_z6_7');
SELECT create_water_areas_centroids_mview('osm_water_areas_z8_9', 'mv_water_areas_centroids_z8_9');
SELECT create_water_areas_centroids_mview('osm_water_areas_z10_12', 'mv_water_areas_centroids_z10_12');
SELECT create_water_areas_centroids_mview('osm_water_areas_z13_15', 'mv_water_areas_centroids_z13_20');

-- ============================================================================
-- Create materialized views for water areas using subdivided geometries and generic function
-- ============================================================================
SELECT create_water_areas_subdivided_mview('osm_water_areas_z0_2', 'mv_water_areas_z0_2_subdivided');
SELECT create_water_areas_subdivided_mview('osm_water_areas_z3_5', 'mv_water_areas_z3_5_subdivided');
SELECT create_water_areas_subdivided_mview('osm_water_areas_z6_7', 'mv_water_areas_z6_7_subdivided');
SELECT create_water_areas_subdivided_mview('osm_water_areas_z8_9', 'mv_water_areas_z8_9_subdivided');
SELECT create_generic_mview('osm_water_areas_z10_12', 'mv_water_areas_z10_12', ARRAY['osm_id', 'type']);
SELECT create_generic_mview('osm_water_areas_z13_15', 'mv_water_areas_z13_15', ARRAY['osm_id', 'type']);
SELECT create_generic_mview('osm_water_areas', 'mv_water_areas_z16_20', ARRAY['osm_id', 'type']);

-- ============================================================================
-- Create materialized views for water lines
-- ============================================================================
SELECT create_generic_mview('osm_water_lines_z8_9', 'mv_water_lines_z8_9');
SELECT create_generic_mview('osm_water_lines_z10_12', 'mv_water_lines_z10_12');
SELECT create_generic_mview('osm_water_lines_z13_15', 'mv_water_lines_z13_15');
SELECT create_generic_mview('osm_water_lines_z16_20', 'mv_water_lines_z16_20');
