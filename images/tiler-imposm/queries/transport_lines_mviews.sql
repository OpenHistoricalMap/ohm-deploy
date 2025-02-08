-- This is an SQL script to merge the transport lines and multilines tables into materialized views.
DO $$ 
DECLARE 
    zoom_levels TEXT[] := ARRAY['_z5_7', '_z8_9', '_z10_11', '_z12_13'];
    zoom TEXT;
    sql_drop TEXT;
    sql_create TEXT;
BEGIN
    FOR zoom IN SELECT UNNEST(zoom_levels)
    LOOP
        -- Drop materialized view if it exists
        sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS mview_transport_lines%s CASCADE;', zoom);
        EXECUTE sql_drop;
        
        -- Construct the SQL query to create the materialized view
        sql_create := format(
            'CREATE MATERIALIZED VIEW mview_transport_lines%s AS
            SELECT
                ''way_'' || CAST(osm_id AS TEXT) AS osm_id, 
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
                ''osm_transport_lines'' AS source_table
            FROM osm_transport_lines%s
            WHERE geometry IS NOT NULL
            UNION ALL
            SELECT DISTINCT ON (osm_id)
                ''relation_'' || CAST(osm_id AS TEXT) || ''_'' || COALESCE(CAST(member AS TEXT), '''') AS osm_id,
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
                ''osm_transport_multilines'' AS source_table
            FROM osm_transport_multilines%s
            WHERE ST_GeometryType(geometry) = ''ST_LineString''
            AND geometry IS NOT NULL;',
            zoom, zoom, zoom
        );

        -- Execute the dynamically generated SQL
        EXECUTE sql_create;
        
        -- Log success message
        RAISE NOTICE 'Created materialized view: mview_transport_lines%s', zoom;
    END LOOP;
END $$;


DO $$ 
DECLARE 
    zoom_levels TEXT[] := ARRAY['_z5_7', '_z8_9', '_z10_11', '_z12_13'];
    zoom TEXT;
    sql_unique_index TEXT;
    sql_geometry TEXT;
BEGIN
    FOR zoom IN SELECT UNNEST(zoom_levels)
    LOOP
        -- Create UNIQUE index using osm_id + type to prevent duplicates
        sql_unique_index := format(
            'CREATE UNIQUE INDEX idx_mview_transport_lines%s_osm_id ON mview_transport_lines%s (osm_id, type);', 
            zoom, zoom
        );
        EXECUTE sql_unique_index;

        -- Create spatial index on geometry
        sql_geometry := format(
            'CREATE INDEX idx_mview_transport_lines%s_geom ON mview_transport_lines%s USING GIST (geometry);', 
            zoom, zoom
        );
        EXECUTE sql_geometry;

        -- Log success message
        RAISE NOTICE 'Indexes created on mview_transport_lines%s', zoom;
    END LOOP;
END $$;