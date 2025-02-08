DO $$ 
DECLARE 
    transport_tables JSONB := '[
        {"lines": "osm_transport_lines_z5_7", "multilines": "osm_transport_multilines_z5_7", "mview": "mview_transport_lines_z5_7"},
        {"lines": "osm_transport_lines_z8_9", "multilines": "osm_transport_multilines_z8_9", "mview": "mview_transport_lines_z8_9"},
        {"lines": "osm_transport_lines_z10_11", "multilines": "osm_transport_multilines_z10_11", "mview": "mview_transport_lines_z10_11"},
        {"lines": "osm_transport_lines_z12_13", "multilines": "osm_transport_multilines_z12_13", "mview": "mview_transport_lines_z12_13"},
        {"lines": "osm_transport_lines", "multilines": "osm_transport_multilines", "mview": "mview_transport_lines_z14_20"}
    ]'::JSONB;

    table_entry JSONB;
    sql_drop TEXT;
    sql_create TEXT;
    sql_unique_index TEXT;
    sql_geometry TEXT;
    column_list TEXT := '
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
        tags';

BEGIN
    RAISE NOTICE 'Starting materialized view creation process...';

    FOR table_entry IN SELECT * FROM jsonb_array_elements(transport_tables)
    LOOP
        RAISE NOTICE 'Processing: %', table_entry;

        -- Drop materialized view if it exists
        sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %s CASCADE;', table_entry->>'mview');
        RAISE NOTICE 'Executing: %', sql_drop;
        EXECUTE sql_drop;

        -- Construct the SQL query using a CTE
        sql_create := format(
            'CREATE MATERIALIZED VIEW %s AS
            WITH selected_columns AS (
                SELECT 
                    ''way_'' || CAST(lines.osm_id AS TEXT) AS osm_id, 
                    %s, 
                    ''%s'' AS source_table
                FROM %s AS lines
                WHERE lines.geometry IS NOT NULL
                UNION ALL
                SELECT DISTINCT ON (multilines.osm_id, multilines.member)
                    ''relation_'' || CAST(multilines.osm_id AS TEXT) || ''_'' || COALESCE(CAST(multilines.member AS TEXT), '''') AS osm_id,
                    %s, 
                    ''%s'' AS source_table
                FROM %s AS multilines
                WHERE ST_GeometryType(multilines.geometry) = ''ST_LineString''
                AND multilines.geometry IS NOT NULL
            )
            SELECT * FROM selected_columns;',
            table_entry->>'mview', column_list, table_entry->>'lines', table_entry->>'lines', 
            column_list, table_entry->>'multilines', table_entry->>'multilines'
        );

        RAISE NOTICE 'Creating materialized view: %', table_entry->>'mview';
        EXECUTE sql_create;
        
        -- Create UNIQUE index to prevent duplicates
        sql_unique_index := format(
            'CREATE UNIQUE INDEX CONCURRENTLY idx_%s_osm_id ON %s (osm_id);', 
            table_entry->>'mview', table_entry->>'mview'
        );
        RAISE NOTICE 'Creating unique index: %', sql_unique_index;
        EXECUTE sql_unique_index;

        -- Create spatial index on geometry
        sql_geometry := format(
            'CREATE INDEX CONCURRENTLY idx_%s_geom ON %s USING GIST (geometry);', 
            table_entry->>'mview', table_entry->>'mview'
        );
        RAISE NOTICE 'Creating spatial index: %', sql_geometry;
        EXECUTE sql_geometry;

        RAISE NOTICE 'Successfully created materialized view and indexes for %', table_entry->>'mview';
    END LOOP;

    RAISE NOTICE 'Materialized view creation process completed!';
END $$;
