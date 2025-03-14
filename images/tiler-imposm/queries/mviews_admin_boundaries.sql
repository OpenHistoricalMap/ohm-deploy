-- This script creates materialized views for admin boundaries. 
-- It creates two materialized views for each zoom level: one for the boundary lines and one for the centroid points.
-- The boundary lines are created using the ST_Boundary function, and the centroid points are created using the ST_MaximumInscribedCircle function. 
-- The script also creates spatial indexes on the geometry column for performance and unique indexes on the osm_id column for concurrent refresh.

DO $$ 
DECLARE 
    zoom_levels TEXT[] := ARRAY['z0_2', 'z3_5', 'z6_7', 'z8_9', 'z10_12', 'z13_15', 'z16_20'];
    zoom TEXT;
    sql_drop_lines TEXT;
    sql_drop_centroid TEXT;
    sql_create_lines TEXT;
    sql_create_centroid TEXT;
    sql_index_lines TEXT;
    sql_index_centroid TEXT;
    sql_unique_index_lines TEXT;
    sql_unique_index_centroid TEXT;
    table_name TEXT;
BEGIN
    RAISE NOTICE '================= Starting materialized view creation for Admin Boundaries =================';

    FOR zoom IN SELECT UNNEST(zoom_levels)
    LOOP
        -- Define the table name dynamically
        table_name := format('osm_admin_areas_%s', zoom);

        RAISE NOTICE 'Processing materialized views for zoom level: %, using table: %', zoom, table_name;

        -- Drop existing materialized views
        sql_drop_lines := format('DROP MATERIALIZED VIEW IF EXISTS mview_admin_boundaries_lines_%s CASCADE;', zoom);
        sql_drop_centroid := format('DROP MATERIALIZED VIEW IF EXISTS mview_admin_boundaries_centroid_%s CASCADE;', zoom);
        
        EXECUTE sql_drop_lines;
        RAISE NOTICE 'Dropped materialized view: mview_admin_boundaries_lines_%s', zoom;

        EXECUTE sql_drop_centroid;
        RAISE NOTICE 'Dropped materialized view: mview_admin_boundaries_centroid_%s', zoom;

        -- Create materialized view for admin boundaries (Lines)
        sql_create_lines := format($sql$
            CREATE MATERIALIZED VIEW mview_admin_boundaries_lines_%s AS
            SELECT
                osm_id,
                name,
                admin_level,
                type,
                ST_Boundary(geometry) AS geometry,
                start_date,
                end_date,
                area,
                tags
            FROM %s;
        $sql$, zoom, table_name);
        
        -- NOTE: Do not create admin lines since we are merging in mviews_admin_boundaries_merged.sql
        EXECUTE sql_create_lines;
        RAISE NOTICE 'Created materialized view: mview_admin_boundaries_lines_%s', zoom;

        -- Create materialized view for admin boundaries (Centroids)
        sql_create_centroid := format($sql$
            CREATE MATERIALIZED VIEW mview_admin_boundaries_centroid_%s AS
            SELECT
                osm_id,
                name,
                admin_level,
                type,
                (ST_MaximumInscribedCircle(geometry)).center AS geometry,
                start_date,
                end_date,
                ROUND(CAST(area AS numeric) / 1000000, 1)::numeric(10,1) AS area_km2, -- Convert m² to km²
                tags
            FROM %s
            WHERE name IS NOT NULL AND name <> ''
                AND osm_id NOT IN (SELECT osm_id FROM osm_relation_members WHERE role = 'label');
        $sql$, zoom, table_name);
        
        EXECUTE sql_create_centroid;
        RAISE NOTICE 'Created materialized view: mview_admin_boundaries_centroid_%s', zoom;

        -- Create Spatial Index for Performance
        sql_index_lines := format('CREATE INDEX IF NOT EXISTS idx_mview_admin_boundaries_lines_%s_geom ON mview_admin_boundaries_lines_%s USING GIST (geometry);', zoom, zoom);
        sql_index_centroid := format('CREATE INDEX IF NOT EXISTS idx_mview_admin_boundaries_centroid_%s_geom ON mview_admin_boundaries_centroid_%s USING GIST (geometry);', zoom, zoom);

        EXECUTE sql_index_lines;
        RAISE NOTICE 'Created spatial index: idx_mview_admin_boundaries_lines_%s_geom', zoom;

        EXECUTE sql_index_centroid;
        RAISE NOTICE 'Created spatial index: idx_mview_admin_boundaries_centroid_%s_geom', zoom;

        -- Create UNIQUE INDEX on osm_id for concurrent refresh
        sql_unique_index_lines := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_mview_admin_boundaries_lines_%s_osm_id ON mview_admin_boundaries_lines_%s (osm_id);', zoom, zoom);
        sql_unique_index_centroid := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_mview_admin_boundaries_centroid_%s_osm_id ON mview_admin_boundaries_centroid_%s (osm_id);', zoom, zoom);

        EXECUTE sql_unique_index_lines;
        RAISE NOTICE 'Created unique index: idx_mview_admin_boundaries_lines_%s_osm_id', zoom;

        EXECUTE sql_unique_index_centroid;
        RAISE NOTICE 'Created unique index: idx_mview_admin_boundaries_centroid_%s_osm_id', zoom;
    END LOOP;

END $$;

-- Refresh Materialized Views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_admin_boundaries_lines_z0_2
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_admin_boundaries_centroid_z0_2
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_admin_boundaries_lines_z3_5
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_admin_boundaries_centroid_z3_5
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_admin_boundaries_lines_z6_7
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_admin_boundaries_centroid_z6_7
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_admin_boundaries_lines_z8_9
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_admin_boundaries_centroid_z8_9
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_admin_boundaries_lines_z10_12
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_admin_boundaries_centroid_z10_12
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_admin_boundaries_lines_z13_15
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_admin_boundaries_centroid_z13_15
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_admin_boundaries_lines_z16_20
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_admin_boundaries_centroid_z16_20
