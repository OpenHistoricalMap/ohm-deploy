-- This script creates materialized views that combine named landuse area centroids
-- and landuse points into a single materialized view to generate a unified layer named "landuse_points_centroids".
-- The function accepts two arguments: the materialized view name and a minimum area threshold.
-- The area threshold filters polygons according to the zoom level at which the points will be displayed.
-- Landuse points are included with a NULL value for the area field.

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
            area, 
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
            NULL AS area, 
            tags
        FROM osm_landuse_points
        WHERE name IS NOT NULL AND name <> '' --Filter points that has a name
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
