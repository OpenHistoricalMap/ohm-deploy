-- ============================================================================
-- Function: create_other_points_centroids_mview
-- Description:
--   This function creates a materialized view that merges centroids of named
--   polygon features from `osm_other_areas` and points from `osm_other_points`
--   into a unified layer named "other_points_centroids".
--
-- Parameters:
--   view_name   TEXT             - The name of the materialized view to be created.
--   min_area    DOUBLE PRECISION - Minimum area (in m²) for polygons to be included.
--                                  This is useful for filtering features by zoom level.
--
-- Notes:
--   - Centroids are calculated using ST_MaximumInscribedCircle for polygons.
--   - Points are included directly with NULL as their area(as an integer) to reduce the size of vector tiles..
--   - Only features with non-empty names are included.
--   - A GiST index is created on geometry for spatial performance.
--   - A unique index is enforced on (osm_id, type, class).
-- ============================================================================

DROP FUNCTION IF EXISTS create_other_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_other_points_centroids_mview(
    view_name TEXT,
    min_area DOUBLE PRECISION DEFAULT 0
)
RETURNS void AS $$
DECLARE 
    sql_drop TEXT;
    sql_create TEXT;
    sql_index TEXT;
    sql_unique_index TEXT;
BEGIN
    RAISE NOTICE 'Creating materialized view: % with area > %', view_name, min_area;

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
            tags
        FROM osm_other_areas
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
            tags
        FROM osm_other_points
        -- WHERE name IS NOT NULL AND name <> ''
    $sql$, view_name, min_area);
    EXECUTE sql_create;

    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;

    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type, class);', view_name, view_name);
    EXECUTE sql_unique_index;

END;
$$ LANGUAGE plpgsql;

SELECT create_other_points_centroids_mview('mview_other_points_centroids_z14_20', 0);
