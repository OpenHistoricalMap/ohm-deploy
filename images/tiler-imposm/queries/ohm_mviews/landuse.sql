-- ============================================================================
-- Function: create_landuse_points_centroids_mview
-- Description:
--   createsa materialized view that merges:
--     - Centroids of polygonal landuse areas using ST_MaximumInscribedCircle
--     - Landuse points directly, with area_m2 set to NULL
--
-- Parameters:
--   view_name    TEXT              - Name of the materialized view.
--   min_area     DOUBLE PRECISION  - Minimum area (in m²) to include landuse areas.
--
-- Notes:
--   - Only includes features with non-empty "name" values.
--   - Multilingual name columns are dynamically added using the `languages` table.
--   - View is recreated if language hash changed or if force_create = TRUE.
--   - Adds GiST index on geometry and a UNIQUE index on (osm_id, type, class).
-- ============================================================================
DROP FUNCTION IF EXISTS create_landuse_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_landuse_points_centroids_mview(
    view_name TEXT,
    min_area DOUBLE PRECISION DEFAULT 0
)
RETURNS void AS $$
DECLARE 
    sql_drop TEXT;
    sql_create TEXT;
    sql_index TEXT;
    sql_unique_index TEXT;
    lang_columns TEXT;
BEGIN
    RAISE NOTICE 'Creating materialized view: % with area > %', view_name, min_area;

    -- Get dynamic language columns from `languages` table
    lang_columns := get_language_columns();

    sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
    EXECUTE sql_drop;

    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            (ST_MaximumInscribedCircle(geometry)).center AS geometry,
            osm_id, 
            name, 
            type, 
            class, 
            start_date, 
            end_date, 
            ROUND(area)::bigint AS area_m2,
            tags,
            %s
        FROM osm_landuse_areas
        WHERE name IS NOT NULL AND name <> '' AND area > %L

        UNION ALL

        SELECT 
            geometry,
            osm_id, 
            name, 
            type, 
            class, 
            start_date, 
            end_date, 
            NULL AS area_m2, 
            tags,
            %s
        FROM osm_landuse_points;
    $sql$, view_name, lang_columns, min_area, lang_columns);
    EXECUTE sql_create;

    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;

    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type, class);', view_name, view_name);
    EXECUTE sql_unique_index;

    RAISE NOTICE 'Materialized view % created successfully.', view_name;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Create materialized views for landuse points centroids
-- ============================================================================
SELECT create_landuse_points_centroids_mview('mv_landuse_points_centroids_z10_11', 500);
SELECT create_landuse_points_centroids_mview('mv_landuse_points_centroids_z12_13', 100);
SELECT create_landuse_points_centroids_mview('mv_landuse_points_centroids_z14_20', 0);


-- ============================================================================
-- Create materialized views for landuse areas
-- ============================================================================
SELECT create_generic_mview( 'osm_landuse_areas_z3_5', 'mv_landuse_areas_z3_5', ARRAY['osm_id', 'type']);
SELECT create_generic_mview( 'osm_landuse_areas_z6_7', 'mv_landuse_areas_z6_7', ARRAY['osm_id', 'type']);
SELECT create_generic_mview( 'osm_landuse_areas_z8_9', 'mv_landuse_areas_z8_9', ARRAY['osm_id', 'type']);
SELECT create_generic_mview( 'osm_landuse_areas_z10_12', 'mv_landuse_areas_z10_12', ARRAY['osm_id', 'type']);
SELECT create_generic_mview( 'osm_landuse_areas_z13_15', 'mv_landuse_areas_z13_15', ARRAY['osm_id', 'type']);

-- ============================================================================
-- Create materialized views for landuse lines
-- ============================================================================
SELECT create_generic_mview( 'osm_landuse_lines', 'mv_landuse_lines_z14_20', ARRAY['osm_id', 'type']);
