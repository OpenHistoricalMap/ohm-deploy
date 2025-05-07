-- This script creates materialized views that combine named building area centroids
-- and named building points into a single materialized view to generate a unified layer named "buildings_points_centroids".
-- The function accepts two arguments: the materialized view name and a minimum area threshold.
-- The area threshold filters polygons according to the zoom level at which the points will be displayed.
-- Building points are included with NULL values for area and height fields.

DROP FUNCTION IF EXISTS create_buildings_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_buildings_points_centroids_mview(
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
    RAISE NOTICE 'Dropping materialized view %', view_name;
    sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
    EXECUTE sql_drop;

    RAISE NOTICE 'Creating materialized view % with area > %', view_name, min_area;
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS

        SELECT
            geometry,
            osm_id,
            name,
            NULL AS height,
            NULL AS area,
            type,
            start_date,
            end_date,
            tags
        FROM osm_buildings_points_named
        WHERE name IS NOT NULL AND name <> ''

        UNION ALL

        SELECT
            (ST_MaximumInscribedCircle(geometry)).center AS geometry,
            osm_id,
            name,
            CASE
			  WHEN height IS NULL OR trim(height) = '' THEN NULL
			  ELSE regexp_replace(height, '[^0-9\.]', '', 'g')::double precision
			END AS height,
            area,
            type,
            start_date,
            end_date,
            tags
        FROM osm_buildings
        WHERE name IS NOT NULL AND name <> '' AND area >= %L

    $sql$, view_name, min_area);
    EXECUTE sql_create;

    RAISE NOTICE 'Creating indexes on %', view_name;
    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_uid ON %I (osm_id, type);', view_name, view_name);
    EXECUTE sql_unique_index;

    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;

    RAISE NOTICE 'Materialized view % created successfully.', view_name;
END;
$$ LANGUAGE plpgsql;


SELECT create_buildings_points_centroids_mview('mview_buildings_points_centroids_z14_20', 0);
