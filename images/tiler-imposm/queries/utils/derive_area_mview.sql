-- ============================================================================
-- Function: derive_area_mview
-- Description:
--   Creates a new materialized view from an existing materialized view with
--   optional geometry simplification, area filtering, and custom WHERE conditions.
--
--   Uses finalize_materialized_view for the temporary swap: the new view is
--   built and indexed under a _tmp name while the old view keeps serving, then
--   both view and indexes are atomically renamed into place.
--
-- Parameters:
--   source          TEXT              - Name of the source materialized view to read from
--   target          TEXT              - Name of the target materialized view to create/replace
--   simplify_tol    DOUBLE PRECISION  - Simplification tolerance in meters (0 = no simplification)
--   min_metric      DOUBLE PRECISION  - Minimum area to include, uses the 'area' column (0 = no filter)
--   unique_columns  TEXT[]            - Columns for the unique index (default: ARRAY['id', 'osm_id'])
--   where_filter    TEXT              - Optional WHERE clause filter (e.g., "type IN ('water', 'pond')"). NULL = no filter
--   exclude_columns TEXT[]            - Optional column names to drop. NULL = none
--   exclude_patterns TEXT[]           - Optional LIKE patterns to drop columns, e.g. 'name\_%'. NULL = none
-- ============================================================================
DROP FUNCTION IF EXISTS derive_area_mview;

CREATE OR REPLACE FUNCTION derive_area_mview(
    source          TEXT,
    target          TEXT,
    simplify_tol    DOUBLE PRECISION DEFAULT 0,
    min_metric      DOUBLE PRECISION DEFAULT 0,
    unique_columns  TEXT[] DEFAULT ARRAY['id', 'osm_id'],
    where_filter    TEXT DEFAULT NULL,
    exclude_columns TEXT[] DEFAULT NULL,
    exclude_patterns TEXT[] DEFAULT NULL
)
RETURNS void AS $$
DECLARE
    cols_no_geom   TEXT;
    sql_create     TEXT;
    tmp_mview_name TEXT := target || '_tmp';
BEGIN
    RAISE NOTICE '==> [MVIEW AREA] Creating % from % (simplify_tol: %, min_metric: %, where_filter: %)', target, source, simplify_tol, min_metric, where_filter;

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
      AND attname <> 'geometry'
      AND (exclude_columns IS NULL OR NOT (attname = ANY(exclude_columns)))
      AND (exclude_patterns IS NULL OR NOT (attname LIKE ANY(exclude_patterns)));

    IF cols_no_geom IS NULL THEN
        RAISE EXCEPTION 'No columns found for %. Make sure the materialized view exists.', source;
    END IF;

    -- Build the CREATE MATERIALIZED VIEW statement
    sql_create := format(
        'CREATE MATERIALIZED VIEW %I AS
         SELECT %s, %s AS geometry
         FROM %I
         WHERE geometry IS NOT NULL',
        tmp_mview_name,
        cols_no_geom,
        CASE
            WHEN simplify_tol > 0
                THEN format('ST_SimplifyPreserveTopology(geometry, %s)', simplify_tol)
            ELSE 'geometry'
        END,
        source
    );

    -- Apply area filter if requested (filters by 'area' column)
    IF min_metric > 0 THEN
        sql_create := sql_create || format(' AND area >= %s', min_metric);
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
