-- ============================================================================
-- Function: create_landuse_centroid_mviews
-- Description:
--   This function creates a materialized view that generates centroid points
--   from named landuse area geometries using ST_MaximumInscribedCircle.
--   It is intended to support generalized vector tiles for specific zoom levels.
--
--   The resulting view includes only features with a non-empty "name", and uses
--   DISTINCT ON (osm_id, type, class) to avoid duplicate geometries.
--
-- Parameters:
--   source_table TEXT - Name of the source table containing polygonal landuse areas.
--   view_name    TEXT - Name of the materialized view to be created.
--
-- Notes:
--   - Only features with a non-null, non-empty "name" are included.
--   - Centroids are calculated for polygon geometries using the center of the
--     maximum inscribed circle, improving label placement.
--   - A GiST index is created on the geometry column for spatial efficiency.
--   - A unique index is created on (osm_id, type, class) to ensure consistency.
--   - Designed for use in rendering landuse labels in vector tile maps.
-- ============================================================================
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
        SELECT DISTINCT ON (osm_id, type, class)
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
    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_osm_id ON %I (osm_id, type, class);', view_name, view_name);
    EXECUTE sql_unique_index;
    RAISE NOTICE 'Created unique index: idx_%_osm_id', view_name;

END;
$$ LANGUAGE plpgsql;

SELECT create_landuse_centroid_mviews('osm_landuse_areas_z3_5', 'mview_landuse_areas_centroid_z3_5');
SELECT create_landuse_centroid_mviews('osm_landuse_areas_z6_7', 'mview_landuse_areas_centroid_z6_7');
SELECT create_landuse_centroid_mviews('osm_landuse_areas_z8_9', 'mview_landuse_areas_centroid_z8_9');
SELECT create_landuse_centroid_mviews('osm_landuse_areas_z10_12', 'mview_landuse_areas_centroid_z10_12');
SELECT create_landuse_centroid_mviews('osm_landuse_areas_z13_15', 'mview_landuse_areas_centroid_z13_15');
