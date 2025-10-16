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
--   view_name       TEXT              - Name of the materialized view to create.
--   include_points  BOOLEAN           - If TRUE, includes features from 'osm_landuse_points'.
--   min_area        DOUBLE PRECISION  - Minimum area (in m²) to include landuse areas.
--
-- Notes:
--   - Only features with a non-empty "name" are included.
--   - Geometry is indexed using GiST.
--   - Uniqueness is enforced on the combination of (osm_id, type, class).
--   - Language-specific name columns are added dynamically from the `languages` table.
--   - Uses finalize_materialized_view() for safety and reusability.
-- ============================================================================

DROP FUNCTION IF EXISTS create_landuse_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_landuse_points_centroids_mview(
    view_name TEXT,
    include_points BOOLEAN,
    min_area DOUBLE PRECISION DEFAULT 0
)
RETURNS void AS $$
DECLARE 
    tmp_view_name TEXT := view_name || '_tmp';
    sql_create TEXT;
    lang_columns TEXT := get_language_columns();
    unique_columns TEXT := 'osm_id, type, class';
BEGIN
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
            isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
            ROUND(area)::bigint AS area_m2,
            %s
        FROM osm_landuse_areas
        WHERE name IS NOT NULL AND name <> '' AND area > %L
    $sql$, tmp_view_name, lang_columns, min_area);

    -- Only add the UNION ALL block if 'include_points' is true.
    IF include_points THEN
        sql_create := sql_create || format($sql$
            UNION ALL
            SELECT 
                geometry,
                osm_id, 
                NULLIF(name, '') AS name, 
                type, 
                class, 
                NULLIF(start_date, '') AS start_date,
                NULLIF(end_date, '') AS end_date,
                isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
                isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
                NULL AS area_m2, 
                %s
            FROM osm_landuse_points
        $sql$, lang_columns);
    END IF;

    sql_create := sql_create || ';';

    PERFORM finalize_materialized_view(
        tmp_view_name,
        view_name,
        unique_columns,
        sql_create
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Create materialized views for landuse points centroids
-- ============================================================================
SELECT create_landuse_points_centroids_mview('mv_landuse_points_centroids_z8_9', FALSE, 25000000);
SELECT create_landuse_points_centroids_mview('mv_landuse_points_centroids_z10_11', FALSE, 1000000);
SELECT create_landuse_points_centroids_mview('mv_landuse_points_centroids_z12_13', FALSE, 10000);
SELECT create_landuse_points_centroids_mview('mv_landuse_points_centroids_z14_20', TRUE, 0);
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
