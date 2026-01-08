DROP FUNCTION IF EXISTS create_mview_line_from_mview(TEXT, TEXT, DOUBLE PRECISION, TEXT);

/**
 * Creates a new materialized view with line geometries from an existing materialized view
 * containing line geometries (linestrings/multilinestrings).
 * 
 * Applies optional geometry simplification for line geometries, useful for rendering
 * at lower zoom levels or when simplifying complex line features.
 * 
 * Uses a temporary view pattern to avoid downtime: creates the new view with a _tmp suffix,
 * then atomically replaces the old view by dropping it and renaming the temporary one.
 *
 * @param source_mview - Name of the source materialized view to read from (must contain line geometries)
 * @param target_mview - Name of the target materialized view to create/replace (will contain line geometries)
 * @param tolerance_meters - Geometry simplification tolerance in meters (0 = no simplification)
 * @param custom_filter - Additional WHERE clause filter (e.g., "type IN ('river', 'stream')")
 */
CREATE OR REPLACE FUNCTION create_mview_line_from_mview(
    source_mview      text,              -- source materialized view with line geometries
    target_mview      text,              -- target materialized view to create (will contain line geometries)
    tolerance_meters  double precision,  -- geometry simplification tolerance (0 = no simplification)
    custom_filter     text DEFAULT NULL  -- extra WHERE filter (e.g. "type IN (...)")
)
RETURNS void AS
$$
DECLARE
    cols_no_geom text;  -- List of all columns except 'geometry'
    sql          text;  -- Dynamic SQL statement being built
    tmp_mview    text;  -- Temporary view name (target_mview + '_tmp')
BEGIN
    -- Generate temporary view name to avoid conflicts during creation
    tmp_mview := target_mview || '_tmp';
    
    -- 1) Get all columns from the source mview except 'geometry'
    --    Uses pg_attribute to query the system catalog directly (works with materialized views)
    SELECT string_agg(quote_ident(attname), ', ' ORDER BY attnum)
    INTO cols_no_geom
    FROM pg_attribute a
    JOIN pg_class c ON a.attrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND c.relname = source_mview
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND attname <> 'geometry';

    IF cols_no_geom IS NULL THEN
        RAISE EXCEPTION 'No columns found for %. Make sure the materialized view exists.', source_mview;
    END IF;

    -- 2) Build the CREATE MATERIALIZED VIEW statement
    --    Creates the view with a temporary name first to avoid downtime
    --    Applies geometry simplification if tolerance_meters > 0
    --    Filters for line geometries (ST_LineString, ST_MultiLineString)
    sql := format(
        'CREATE MATERIALIZED VIEW %I AS
         SELECT %s, %s AS geometry
         FROM %I
         WHERE geometry IS NOT NULL
           AND ST_GeometryType(geometry) IN (''ST_LineString'', ''ST_MultiLineString'')',
        tmp_mview,
        cols_no_geom,
        CASE 
            WHEN tolerance_meters > 0 
                THEN format('ST_SimplifyPreserveTopology(geometry, %s)', tolerance_meters)
            ELSE 'geometry'
        END,
        source_mview
    );

    -- 3) Apply custom filter if provided (allows additional WHERE conditions)
    IF custom_filter IS NOT NULL AND length(trim(custom_filter)) > 0 THEN
        sql := sql || ' AND ' || custom_filter;
    END IF;

    -- 5) Execute the CREATE MATERIALIZED VIEW statement
    --    This creates the view with the temporary name
    EXECUTE sql;

    -- 6) Create indexes on the temporary view
    --    These will be renamed later to match the final view name
    EXECUTE format(
        'CREATE UNIQUE INDEX IF NOT EXISTS %I_id_osm_id_uidx
         ON %I (id, osm_id)',
        tmp_mview, tmp_mview
    );

    EXECUTE format(
        'CREATE INDEX IF NOT EXISTS %I_geom_idx
         ON %I USING GIST (geometry)',
        tmp_mview, tmp_mview
    );

    -- 7) Drop the old materialized view if it exists
    --    This is safe because we've already created the new one with a different name
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I', target_mview);

    -- 8) Atomically rename the temporary view to the final name
    --    This ensures zero downtime - the view is available immediately after rename
    EXECUTE format('ALTER MATERIALIZED VIEW %I RENAME TO %I', tmp_mview, target_mview);

    -- 9) Rename indexes to match the final view name
    --    This keeps index names consistent with the view name
    EXECUTE format(
        'ALTER INDEX IF EXISTS %I_id_osm_id_uidx RENAME TO %I_id_osm_id_uidx',
        tmp_mview, target_mview
    );

    EXECUTE format(
        'ALTER INDEX IF EXISTS %I_geom_idx RENAME TO %I_geom_idx',
        tmp_mview, target_mview
    );
END;
$$ LANGUAGE plpgsql;
