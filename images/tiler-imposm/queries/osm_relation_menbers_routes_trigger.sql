DO $$
BEGIN
    -- Check if the table exists
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'osm_relation_members_routes'
    ) THEN
        -- Create the trigger function
        CREATE OR REPLACE FUNCTION update_osm_relation_members_routes_merged()
        RETURNS TRIGGER AS $$
        BEGIN
            -- Handle DELETE operation
            IF (TG_OP = 'DELETE') THEN
                DELETE FROM osm_relation_members_routes_merged
                WHERE osm_id = OLD.osm_id;
                RETURN OLD;
            END IF;

            -- Handle INSERT and UPDATE operations
            IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
                -- Merge geometry and update the aggregated row
                INSERT INTO osm_relation_members_routes_merged (
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
                    geometry
                )
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
                FROM osm_relation_members_routes
                WHERE osm_id = NEW.osm_id
                GROUP BY 
                    osm_id, name, type, route, ref, network, direction, operator,
                    state, symbol, distance, roundtrip, interval, duration, tourism,
                    start_date, end_date, tags
                ON CONFLICT (osm_id)
                DO UPDATE SET
                    name = EXCLUDED.name,
                    type = EXCLUDED.type,
                    route = EXCLUDED.route,
                    ref = EXCLUDED.ref,
                    network = EXCLUDED.network,
                    direction = EXCLUDED.direction,
                    operator = EXCLUDED.operator,
                    state = EXCLUDED.state,
                    symbol = EXCLUDED.symbol,
                    distance = EXCLUDED.distance,
                    roundtrip = EXCLUDED.roundtrip,
                    interval = EXCLUDED.interval,
                    duration = EXCLUDED.duration,
                    tourism = EXCLUDED.tourism,
                    start_date = EXCLUDED.start_date,
                    end_date = EXCLUDED.end_date,
                    tags = EXCLUDED.tags,
                    geometry = EXCLUDED.geometry;
                RETURN NEW;
            END IF;
        END;
        $$ LANGUAGE plpgsql;

        -- Attach the trigger to the table
        CREATE TRIGGER osm_relation_members_routes_trigger
        AFTER INSERT OR UPDATE OR DELETE ON osm_relation_members_routes
        FOR EACH ROW
        EXECUTE FUNCTION update_osm_relation_members_routes_merged();

    ELSE
        -- Log or handle the case where the table doesn't exist
        RAISE NOTICE 'Table osm_relation_members_routes does not exist. Skipping trigger creation.';
    END IF;
END;
$$;