-- This script creates materialized views that combine named amenity area centroids
-- and amenity points into a single materialized view to generate a unified layer named "amenity_points_centroids".
-- The function accepts two arguments: the materialized view name and a minimum area threshold.
-- The area threshold filters polygons according to the zoom level at which the points will be displayed.
-- Amenity points are included with a NULL value for the area field.

DROP FUNCTION IF EXISTS create_amenity_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_amenity_points_centroids_mview(
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
            area, 
            start_date, 
            end_date, 
            tags
        FROM osm_amenity_areas
        WHERE name IS NOT NULL AND name <> '' AND area > %L

        UNION ALL

        SELECT 
            geometry,
            osm_id, 
            name, 
            type, 
            NULL AS area, 
            start_date, 
            end_date,
            tags
        FROM osm_amenity_points
    $sql$, view_name, min_area);
    EXECUTE sql_create;

    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;

    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type);', view_name, view_name);
    EXECUTE sql_unique_index;

END;
$$ LANGUAGE plpgsql;

SELECT create_amenity_points_centroids_mview('mview_amenity_points_centroids_z14_20', 0);
