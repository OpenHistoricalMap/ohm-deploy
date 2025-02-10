DO $$ 
DECLARE 
    zoom_levels TEXT[] := ARRAY['z0_2', 'z3_5', 'z6_7', 'z8_9', 'z10_12', 'z13_15'];
    zoom TEXT;
    source_table TEXT;
    view_name TEXT;
    sql_drop TEXT;
    sql_create TEXT;
    sql_index TEXT;
    sql_unique_index TEXT;
BEGIN
    RAISE NOTICE '========== Starting materialized view creation for water areas ==========';

    FOR zoom IN SELECT UNNEST(zoom_levels)
    LOOP
        -- Define source table and materialized view name dynamically
        source_table := format('osm_water_areas_%s', zoom);
        view_name := format('mview_water_areas_centroid_%s', zoom);
        
        RAISE NOTICE 'Processing: Source Table: % | Materialized View: %', source_table, view_name;

        -- Drop materialized view if it exists
        sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %s CASCADE;', view_name);
        EXECUTE sql_drop;
        RAISE NOTICE 'Dropped materialized view: %s', view_name;

        -- Construct materialized view creation SQL
        sql_create := format($sql$
            CREATE MATERIALIZED VIEW %s AS
            SELECT
                osm_id,
                name,
                type,
                start_date,
                end_date,
                tags,
                (ST_MaximumInscribedCircle(geometry)).center AS geometry
            FROM %s
            WHERE name IS NOT NULL AND name <> '';
        $sql$, view_name, source_table);

        EXECUTE sql_create;
        RAISE NOTICE 'Created materialized view: %s', view_name;

        -- Create spatial index on geometry
        sql_index := format('CREATE INDEX IF NOT EXISTS idx_%s_geom ON %s USING GIST (geometry);', view_name, view_name);
        EXECUTE sql_index;
        RAISE NOTICE 'Created spatial index: idx_%s_geom', view_name;

        -- Create unique index on osm_id to allow concurrent refresh
        sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%s_osm_id ON %s (osm_id);', view_name, view_name);
        EXECUTE sql_unique_index;
        RAISE NOTICE 'Created unique index: idx_%s_osm_id', view_name;
    END LOOP;

END $$;
