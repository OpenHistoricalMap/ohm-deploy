-- ============================================================================
-- Function: create_landuse_points_centroids_mview
-- Description:
--   Creates a materialized view that merges named centroids from polygonal 
--   landuse areas and named landuse points into a unified layer.
--
--   For polygonal features, centroids are calculated using ST_MaximumInscribedCircle,
--   and area is stored in square meters (as integer). Point features are included 
--   directly with area set to NULL.
--
--   Temporal fields `start_date` and `end_date` are included as-is, and 
--   additional precalculated columns `start_decdate` and `end_decdate` 
--   are generated using the `isodatetodecimaldate` function.
--
-- Parameters:
--   view_name     TEXT              - Name of the materialized view to create.
--   min_area      DOUBLE PRECISION - Minimum area (in m²) to include landuse areas.
--
-- Notes:
--   - Only features with a non-empty "name" are included.
--   - Geometry is indexed using GiST.
--   - Uniqueness is enforced on the combination of (osm_id, type, class).
--   - Language-specific name columns are added dynamically from the `languages` table.
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
            NULLIF(name, '') AS name, 
            type, 
            class, 
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
            ROUND(area)::bigint AS area_m2,
            %s
        FROM osm_landuse_areas
        WHERE name IS NOT NULL AND name <> '' AND area > %L

        UNION ALL

        SELECT 
            geometry,
            osm_id, 
            NULLIF(name, '') AS name, 
            type, 
            class, 
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
            NULL AS area_m2, 
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
SELECT create_generic_mview( 'osm_landuse_areas', 'mv_landuse_areas_z16_20', ARRAY['osm_id', 'type']);

-- ============================================================================
-- Create materialized views for landuse lines
-- ============================================================================
SELECT create_generic_mview( 'osm_landuse_lines', 'mv_landuse_lines_z14_20', ARRAY['osm_id', 'type', 'class']);
