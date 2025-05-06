-- This script creates materialized views to merge points and centroids of landuse areas
DROP FUNCTION IF EXISTS create_landuse_centroid_point_mview;
CREATE OR REPLACE FUNCTION create_landuse_centroid_point_mview(
    source_table TEXT,
    view_name TEXT
)
RETURNS void AS $$
DECLARE 
    sql_drop TEXT;
    sql_create TEXT;
    sql_index TEXT;
    sql_unique_index TEXT;
BEGIN
    RAISE NOTICE 'Creating materialized view: % from %', view_name, source_table;

    sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
    EXECUTE sql_drop;

    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            md5('area_' || osm_id::text) AS id,
            (ST_MaximumInscribedCircle(geometry)).center AS geometry,
            osm_id, 
            name, 
            type, 
            class, 
            start_date, 
            end_date, 
            area, 
            tags
        FROM %I
        WHERE name IS NOT NULL AND name <> ''

        UNION ALL

        SELECT 
            md5('point_' || osm_id::text) AS id,
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
        WHERE name IS NOT NULL AND name <> ''
    $sql$, view_name, source_table);
    EXECUTE sql_create;

    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;

    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (id);', view_name, view_name);
    EXECUTE sql_unique_index;

END;
$$ LANGUAGE plpgsql;


SELECT create_landuse_points_centroid_mviews('osm_landuse_areas_z3_5', 'mview_landuse_points_centroids_z3_5');
SELECT create_landuse_points_centroid_mviews('osm_landuse_areas_z6_7', 'mview_landuse_points_centroids_z6_7');
SELECT create_landuse_points_centroid_mviews('osm_landuse_areas_z8_9', 'mview_landuse_points_centroids_z8_9');
SELECT create_landuse_points_centroid_mviews('osm_landuse_areas_z10_12', 'mview_landuse_points_centroids_z10_12');
SELECT create_landuse_points_centroid_mviews('osm_landuse_areas_z13_15', 'mview_landuse_points_centroids_z13_15');
