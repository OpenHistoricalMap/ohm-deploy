DO $$ 
DECLARE 
    zoom_levels TEXT[] := ARRAY['_z5_7', '_z8_9', '_z10_11', '_z12_13', '_z14_20'];
    zoom TEXT;
    sql_drop TEXT;
    sql_create TEXT;
    sql_unique_index TEXT;
    sql_geometry_index TEXT;
    lines_table TEXT;
    multilines_table TEXT;
BEGIN
    RAISE NOTICE '=================Starting materialized view creation for  Transport lines =================';

    FOR zoom IN SELECT UNNEST(zoom_levels)
    LOOP
        -- Special case for _z14_20, use base tables without zoom suffix
        IF zoom = '_z14_20' THEN
            lines_table := 'osm_transport_lines';
            multilines_table := 'osm_transport_multilines';
        ELSE
            lines_table := format('osm_transport_lines%s', zoom);
            multilines_table := format('osm_transport_multilines%s', zoom);
        END IF;

        RAISE NOTICE 'Processing: {"lines": "%s", "mview": "mview_transport_lines%s", "multilines": "%s"}', 
                     lines_table, zoom, multilines_table;

        -- Drop materialized view if it exists
        sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS mview_transport_lines%s CASCADE;', zoom);
        RAISE NOTICE 'Executing: %s', sql_drop;
        EXECUTE sql_drop;

        RAISE NOTICE 'Creating materialized view: mview_transport_lines%s', zoom;

        -- Construct the SQL query to create the materialized view
        sql_create := format($sql$
            CREATE MATERIALIZED VIEW mview_transport_lines%s AS
            SELECT DISTINCT ON (osm_id, type) 
                md5(COALESCE(CAST(osm_id AS TEXT), '') || '_' || COALESCE(type, '')) AS id, 
                osm_id,
                geometry,
                type,
                name,
                tunnel,
                bridge,
                oneway,
                ref,
                z_order,
                access,
                service,
                ford,
                class,
                electrified,
                highspeed,
                usage,
                railway,
                aeroway,
                highway,
                route,
                start_date,
                end_date,
                tags,
                NULL AS member, -- No member in osm_transport_lines
                'osm_transport_lines' AS source_table
            FROM %s
            WHERE geometry IS NOT NULL

            UNION ALL

            SELECT DISTINCT ON (osm_id, type, member)
                md5(COALESCE(CAST(osm_id AS TEXT), '') || '_' || COALESCE(CAST(member AS TEXT), '') || '_' || COALESCE(type, '')) AS id,
                osm_id,
                geometry,
                type,
                name,
                tunnel,
                bridge,
                oneway,
                ref,
                z_order,
                access,
                service,
                ford,
                class,
                electrified,
                highspeed,
                usage,
                railway,
                aeroway,
                highway,
                route,
                start_date,
                end_date,
                tags,
                member, -- Include member from osm_transport_multilines
                'osm_transport_multilines' AS source_table
            FROM %s
            WHERE ST_GeometryType(geometry) = 'ST_LineString'
            AND geometry IS NOT NULL;
        $sql$, zoom, lines_table, multilines_table);

        RAISE NOTICE 'Executing materialized view creation SQL for: mview_transport_lines%s', zoom;
        EXECUTE sql_create;

        RAISE NOTICE 'Successfully created materialized view: mview_transport_lines%s', zoom;

        -- Create UNIQUE index using `id` for safe CONCURRENT REFRESH
        sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_mview_transport_lines%s_osm_id ON mview_transport_lines%s (id);', zoom, zoom);
        RAISE NOTICE 'Executing: %s', sql_unique_index;
        EXECUTE sql_unique_index;

        -- Create spatial index on geometry for fast spatial queries
        sql_geometry_index := format('CREATE INDEX IF NOT EXISTS idx_mview_transport_lines%s_geom ON mview_transport_lines%s USING GIST (geometry);', zoom, zoom);
        RAISE NOTICE 'Executing: %s', sql_geometry_index;
        EXECUTE sql_geometry_index;

        RAISE NOTICE 'Indexes successfully created for mview_transport_lines%s', zoom;
    END LOOP;

    RAISE NOTICE 'Materialized view and index creation process completed successfully!';
END $$;

-- Refresh Materialized Views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_transport_lines_z5_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_transport_lines_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_transport_lines_z10_11;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_transport_lines_z12_13;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mview_transport_lines_z14_20;