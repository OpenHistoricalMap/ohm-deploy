-- ============================================================================
-- Function: derive_line_mview
-- Description:
--   Creates a new materialized view with line geometries from an existing
--   materialized view containing line geometries (linestrings/multilinestrings).
--
--   Applies optional geometry simplification and minimum length filtering,
--   useful for rendering at lower zoom levels or when simplifying complex
--   line features.
--
--   Uses finalize_materialized_view for the temporary swap: the new view is
--   built and indexed under a _tmp name while the old view keeps serving, then
--   both view and indexes are atomically renamed into place.
--
-- Parameters:
--   source          TEXT              - Name of the source materialized view to read from (must contain line geometries)
--   target          TEXT              - Name of the target materialized view to create/replace
--   simplify_tol    DOUBLE PRECISION  - Simplification tolerance in meters (0 = no simplification)
--   min_metric      DOUBLE PRECISION  - Minimum length in m to include, uses ST_Length(geometry) (0 = no filter)
--   unique_columns  TEXT[]            - Columns for the unique index (default: ARRAY['id', 'osm_id'])
--   where_filter    TEXT              - Optional WHERE clause filter (e.g., "type IN ('river', 'stream')"). NULL = no filter
-- ============================================================================
-- Legacy signatures (pre-standardization, issue #1372)
DROP FUNCTION IF EXISTS create_mview_line_from_mview(TEXT, TEXT, DOUBLE PRECISION, TEXT);
DROP FUNCTION IF EXISTS derive_line_mview(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT);
DROP FUNCTION IF EXISTS derive_line_mview(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT[], TEXT);

CREATE OR REPLACE FUNCTION derive_line_mview(
    source          TEXT,
    target          TEXT,
    simplify_tol    DOUBLE PRECISION DEFAULT 0,
    min_metric      DOUBLE PRECISION DEFAULT 0,
    unique_columns  TEXT[] DEFAULT ARRAY['id', 'osm_id'],
    where_filter    TEXT DEFAULT NULL
)
RETURNS void AS $$
DECLARE
    cols_no_geom   TEXT;
    sql_create     TEXT;
    tmp_mview_name TEXT := target || '_tmp';
BEGIN
    RAISE NOTICE '==> [MVIEW LINE] Creating % from % (simplify_tol: %, min_metric: %, where_filter: %)', target, source, simplify_tol, min_metric, where_filter;

    -- Get all columns from the source mview except 'geometry'
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

    -- Build the CREATE MATERIALIZED VIEW statement
    sql_create := format(
        'CREATE MATERIALIZED VIEW %I AS
         SELECT %s, %s AS geometry
         FROM %I
         WHERE geometry IS NOT NULL
           AND ST_GeometryType(geometry) IN (''ST_LineString'', ''ST_MultiLineString'')',
        tmp_mview_name,
        cols_no_geom,
        CASE
            WHEN simplify_tol > 0
                THEN format('ST_SimplifyPreserveTopology(geometry, %s)', simplify_tol)
            ELSE 'geometry'
        END,
        source
    );

    -- Apply length filter if requested
    IF min_metric > 0 THEN
        sql_create := sql_create || format(' AND ST_Length(geometry) >= %s', min_metric);
    END IF;

    -- Apply custom filter if provided (allows additional WHERE conditions)
    IF where_filter IS NOT NULL AND length(trim(where_filter)) > 0 THEN
        sql_create := sql_create || format(' AND (%s)', where_filter);
    END IF;

    PERFORM finalize_materialized_view(
        tmp_mview_name,
        target,
        array_to_string(unique_columns, ', '),
        sql_create
    );
END;
$$ LANGUAGE plpgsql;
