DO $$
BEGIN
    -- Check if the table osm_relation_members_routes exists
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'osm_relation_members_routes'
    ) THEN
        -- Drop the merged table if it exists
        DROP TABLE IF EXISTS osm_relation_members_routes_merged;

        -- Create the merged table
        CREATE TABLE osm_relation_members_routes_merged AS
        SELECT 
            osm_id,
            name,
            type,
            route,
            ref,
            network,
            direction,
            operator,
            state,
            symbol,
            distance,
            roundtrip,
            interval,
            duration,
            tourism,
            start_date,
            end_date,
            tags,
            ST_Union(geometry) AS geometry
        FROM 
            osm_relation_members_routes
        GROUP BY 
            osm_id, name, type, route, ref, network, direction, operator,
            state, symbol, distance, roundtrip, interval, duration, tourism,
            start_date, end_date, tags;

        -- Add primary key
        ALTER TABLE osm_relation_members_routes_merged ADD PRIMARY KEY (osm_id);

        -- Create geometry index
        CREATE INDEX idx_osm_relation_members_routes_merged_geometry
        ON osm_relation_members_routes_merged
        USING GIST (geometry);

        RAISE NOTICE 'Merged table created successfully.';
    ELSE
        RAISE NOTICE 'Table osm_relation_members_routes does not exist. Skipping execution.';
    END IF;
END $$;