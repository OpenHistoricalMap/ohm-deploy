-- ============================================================================
-- Function: derive_area_mview
-- Description:
--   Creates a new materialized view from an existing materialized view with
--   optional geometry simplification, area filtering, and custom WHERE conditions.
--
--   Uses a temporary view pattern to avoid downtime: creates the new view with a
--   _tmp suffix, then atomically replaces the old view by dropping it and
--   renaming the temporary one.
--
-- Parameters:
--   source        TEXT              - Name of the source materialized view to read from
--   target        TEXT              - Name of the target materialized view to create/replace
--   simplify_tol  DOUBLE PRECISION  - Simplification tolerance in meters (0 = no simplification)
--   min_metric    DOUBLE PRECISION  - Minimum area to include, uses the 'area' column (0 = no filter)
--   where_filter  TEXT              - Optional WHERE clause filter (e.g., "type IN ('water', 'pond')"). NULL = no filter
-- ============================================================================
-- Legacy signature (pre-standardization, issue #1372)
DROP FUNCTION IF EXISTS create_area_mview_from_mview(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT);
DROP FUNCTION IF EXISTS derive_area_mview(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT);

CREATE OR REPLACE FUNCTION derive_area_mview(
    source        TEXT,
    target        TEXT,
    simplify_tol  DOUBLE PRECISION DEFAULT 0,
    min_metric    DOUBLE PRECISION DEFAULT 0,
    where_filter  TEXT DEFAULT NULL
)
RETURNS void AS
$$
DECLARE
    cols_no_geom text;
    sql          text;
    tmp_mview    text;
BEGIN
    RAISE NOTICE '==> [MVIEW AREA] Creating % from % (simplify_tol: %m, min_metric: %s, where_filter: %s)', target, source, simplify_tol, min_metric, where_filter;
    -- Generate temporary view name to avoid conflicts during creation
    tmp_mview := target || '_tmp';

    -- 1) Get all columns from the source mview except 'geometry'
    SELECT string_agg(quote_ident(attname), ', ' ORDER BY attnum)
    INTO cols_no_geom
    FROM pg_attribute a
    JOIN pg_class c ON a.attrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND c.relname = source
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND attname <> 'geometry';

    IF cols_no_geom IS NULL THEN
        RAISE EXCEPTION 'No columns found for %. Make sure the materialized view exists.', source;
    END IF;

    -- 2) Build the CREATE MATERIALIZED VIEW statement
    sql := format(
        'CREATE MATERIALIZED VIEW %I AS
         SELECT %s, %s AS geometry
         FROM %I
         WHERE geometry IS NOT NULL',
        tmp_mview,
        cols_no_geom,
        CASE
            WHEN simplify_tol > 0
                THEN format('ST_SimplifyPreserveTopology(geometry, %s)', simplify_tol)
            ELSE 'geometry'
        END,
        source
    );

    -- 3) Apply area filter if requested (filters by 'area' column)
    IF min_metric > 0 THEN
        sql := sql || format(' AND area >= %s', min_metric);
    END IF;

    -- 4) Apply custom filter if provided (allows additional WHERE conditions)
    IF where_filter IS NOT NULL AND length(trim(where_filter)) > 0 THEN
        sql := sql || ' AND ' || where_filter;
    END IF;

    -- 5) Execute the CREATE MATERIALIZED VIEW statement
    EXECUTE sql;

    -- 6) Create indexes on the temporary view
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
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I', target);

    -- 8) Atomically rename the temporary view to the final name
    EXECUTE format('ALTER MATERIALIZED VIEW %I RENAME TO %I', tmp_mview, target);

    -- 9) Rename indexes to match the final view name
    EXECUTE format(
        'ALTER INDEX IF EXISTS %I_id_osm_id_uidx RENAME TO %I_id_osm_id_uidx',
        tmp_mview, target
    );

    EXECUTE format(
        'ALTER INDEX IF EXISTS %I_geom_idx RENAME TO %I_geom_idx',
        tmp_mview, target
    );
END;
$$ LANGUAGE plpgsql;
