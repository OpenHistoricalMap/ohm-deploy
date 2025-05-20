-- This script creates materialized views for  water cetroids fore each zoom levels.
DROP FUNCTION IF EXISTS create_landuse_centroid_mviews;
CREATE OR REPLACE FUNCTION create_landuse_centroid_mviews(
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
    RAISE NOTICE 'Creating centroid materialized view from % to %', source_table, view_name;

    -- Drop existing materialized view
    sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
    EXECUTE sql_drop;
    RAISE NOTICE 'Dropped materialized view: %', view_name;

    -- Create the materialized view with centroid geometry
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            osm_id,
            name,
            type,
            class,
            start_date,
            end_date,
            area,
            tags,
            (ST_MaximumInscribedCircle(geometry)).center AS geometry
        FROM %I
        WHERE name IS NOT NULL AND name <> '';
    $sql$, view_name, source_table);
    EXECUTE sql_create;
    RAISE NOTICE 'Created materialized view: %', view_name;

    -- Create spatial index
    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;
    RAISE NOTICE 'Created spatial index: idx_%_geom', view_name;

    -- Create unique index on osm_id
    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_osm_id ON %I (osm_id, type);', view_name, view_name);
    EXECUTE sql_unique_index;
    RAISE NOTICE 'Created unique index: idx_%_osm_id', view_name;

END;
$$ LANGUAGE plpgsql;

SELECT create_landuse_centroid_mviews('osm_landuse_areas_z3_5', 'mview_landuse_areas_centroid_z3_5');
SELECT create_landuse_centroid_mviews('osm_landuse_areas_z6_7', 'mview_landuse_areas_centroid_z6_7');
SELECT create_landuse_centroid_mviews('osm_landuse_areas_z8_9', 'mview_landuse_areas_centroid_z8_9');
SELECT create_landuse_centroid_mviews('osm_landuse_areas_z10_12', 'mview_landuse_areas_centroid_z10_12');
SELECT create_landuse_centroid_mviews('osm_landuse_areas_z13_15', 'mview_landuse_areas_centroid_z13_15');
