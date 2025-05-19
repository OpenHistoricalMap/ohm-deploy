-- ============================================================================
-- Function: create_landuse_points_centroids_mview
-- Description:
--   This script creates a materialized view that merges named centroids from
--   polygonal landuse areas and named landuse points into a unified layer called 
--   "landuse_points_centroids".
--
--   Centroids are calculated using ST_MaximumInscribedCircle on the area geometries,
--   while landuse points are included directly, with the area field set to NULL.
--
-- Parameters:
--   view_name   TEXT             - The name of the materialized view to create.
--   min_area    DOUBLE PRECISION - Minimum area (in m²) required to include a landuse area.
--
-- Notes:
--   - Only features with non-empty "name" values are included.
--   - The resulting view is optimized for vector tiles at different zoom levels.
--   - The area is stored in square meters (area_m2) as an integer to minimize tile size.
--   - Geometry is indexed using GiST; uniqueness is enforced on (osm_id, type, class).
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
        FROM osm_landuse_areas
        WHERE name IS NOT NULL AND name <> '' AND area > %L --Filter centroids that has a name

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
        FROM osm_landuse_points
    $sql$, view_name, min_area);
    EXECUTE sql_create;

    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;

    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type, class);', view_name, view_name);
    EXECUTE sql_unique_index;

END;
$$ LANGUAGE plpgsql;

SELECT create_landuse_points_centroids_mview('mview_landuse_points_centroids_z10_11', 500);
SELECT create_landuse_points_centroids_mview('mview_landuse_points_centroids_z12_13', 100);
SELECT create_landuse_points_centroids_mview('mview_landuse_points_centroids_z14_20', 0);
