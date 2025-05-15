-- ============================================================================
-- Function: create_transport_points_centroids_mview
-- Description:
--   This function creates a materialized view that merges transport area centroids 
--   (calculated from polygons) and transport points into a unified layer.
--
-- Parameters:
--   view_name   TEXT             - The name of the materialized view to create.
--   min_area    DOUBLE PRECISION - The minimum area (in m²) for including transport areas.
--                                  Used to filter polygon features based on zoom levels.
--
-- Notes:
--   - Centroids are computed using ST_MaximumInscribedCircle for polygonal geometries.
--   - Transport points are included directly and will have a NULL value for area_m2 (as an integer) to reduce the size of vector tiles.
--   - Only features with a non-empty "name"  from areas table are included.
--   - The resulting view is useful for rendering transport labels at appropriate zoom levels.
--   - A GiST index is created on geometry, and uniqueness is enforced on (osm_id, type, class).
-- ============================================================================

DROP FUNCTION IF EXISTS create_transport_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_transport_points_centroids_mview(
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
            class, 
            type, 
            start_date, 
            end_date, 
            ROUND(area)::bigint AS area_m2,
            tags
        FROM osm_transport_areas
        WHERE name IS NOT NULL AND name <> '' AND area > %L

        UNION ALL

        SELECT 
            geometry,
            osm_id, 
            name, 
            class, 
            type, 
            start_date, 
            end_date, 
            NULL AS area_m2, 
            tags
        FROM osm_transport_points
    $sql$, view_name, min_area);
    EXECUTE sql_create;

    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;

    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type, class);', view_name, view_name);
    EXECUTE sql_unique_index;

END;
$$ LANGUAGE plpgsql;


SELECT create_transport_points_centroids_mview('mview_transport_points_centroids_z14_20', 0);
