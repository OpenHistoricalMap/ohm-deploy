-- ============================================================================
-- Function: create_point_mview
-- Description:
--   Creates a points materialized view by adding necessary columns:
--   - start_decdate: calculated from start_date
--   - end_decdate: calculated from end_date
--   - area_m2: NULL (points don't have area)
--   - area_km2: NULL (points don't have area)
--   - Language columns from tags using get_language_columns()
--   - source: 'point' to identify the origin
--
--   Uses finalize_materialized_view to create the view safely and consistently.
--
-- Parameters:
--   source           TEXT    - Name of the source points table
--   target           TEXT    - Name of the materialized view to create
--   unique_columns   TEXT[]  - Columns for the unique index (default: ARRAY['id', 'source', 'osm_id'])
--   where_filter     TEXT    - Optional WHERE clause filter. NULL = no filter
--   column_overrides JSONB   - Optional mapping {column_name: sql_expression}. If the column exists
--                              in the source table its default expression is replaced; if it does
--                              not exist, it is added as a new column. NULL = none
--   exclude_columns  TEXT[]  - Optional list of source-table columns to omit from the mview output. NULL = none
--
-- Notes:
--   - Creates a MATERIALIZED VIEW (not a table) using a temporary swap mechanism
--   - Adds a spatial index (GiST) on geometry and a unique index on unique_columns
--   - Output columns match the structure produced by create_area_mview so point
--     and polygon mviews can be merged later (e.g. by derive_centroid_mview)
--   - column_overrides expressions are used as-is; use double single quotes ('')
--     inside expressions for string literals
-- ============================================================================
DROP FUNCTION IF EXISTS create_point_mview;

CREATE OR REPLACE FUNCTION create_point_mview(
    source           TEXT,
    target           TEXT,
    unique_columns   TEXT[] DEFAULT ARRAY['id', 'source', 'osm_id'],
    where_filter     TEXT DEFAULT NULL,
    column_overrides JSONB DEFAULT NULL,
    exclude_columns  TEXT[] DEFAULT NULL
)
RETURNS void AS $$
DECLARE
    lang_columns TEXT;
    sql_create TEXT;
    tmp_view_name TEXT := target || '_tmp';
    custom_filter TEXT;
    all_cols TEXT;
    override_key TEXT;
    override_expr TEXT;
BEGIN
    -- Language columns will always be available
    lang_columns := get_language_columns();

    -- Build custom WHERE filter (if provided)
    IF where_filter IS NOT NULL AND where_filter <> '' THEN
        custom_filter := format(' AND (%s)', where_filter);
    ELSE
        custom_filter := '';
    END IF;

    -- Build SQL - get all columns from the source table and handle special columns
    -- Exclude start_decdate, end_decdate and area columns because they will be recalculated
    -- column_overrides (if provided) takes precedence and fully replaces the default expression for a column
    SELECT COALESCE(string_agg(
        CASE
            WHEN column_overrides IS NOT NULL AND column_overrides ? column_name THEN
                format('%s AS %I', column_overrides->>column_name, column_name)
            WHEN column_name = 'name' THEN 'NULLIF(name, '''') AS name'
            WHEN column_name = 'start_date' THEN 'NULLIF(start_date, '''') AS start_date'
            WHEN column_name = 'end_date' THEN 'NULLIF(end_date, '''') AS end_date'
            ELSE quote_ident(column_name)
        END,
        ', ' ORDER BY ordinal_position
    ), '')
    INTO all_cols
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = source
      AND column_name NOT IN ('start_decdate', 'end_decdate', 'area', 'area_m2', 'area_km2')
      AND (exclude_columns IS NULL OR NOT (column_name = ANY(exclude_columns)));

    -- Always add calculated date columns
    all_cols := all_cols || ', public.isodatetodecimaldate(public.pad_date(start_date, ''start''), FALSE) AS start_decdate';
    all_cols := all_cols || ', public.isodatetodecimaldate(public.pad_date(end_date, ''end''), FALSE) AS end_decdate';

    -- Add area columns (NULL for points) - must match the polygon mview structure
    all_cols := all_cols || ', NULL::numeric AS area';
    all_cols := all_cols || ', NULL::numeric AS area_m2';
    all_cols := all_cols || ', NULL::numeric AS area_km2';

    -- Add language columns (always available)
    all_cols := all_cols || ', ' || lang_columns;

    -- Override keys that do not exist in the source table are added as new columns
    IF column_overrides IS NOT NULL THEN
        FOR override_key, override_expr IN SELECT key, value FROM jsonb_each_text(column_overrides)
        LOOP
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name = source
                  AND column_name = override_key
            ) THEN
                all_cols := all_cols || format(', %s AS %I', override_expr, override_key);
            END IF;
        END LOOP;
    END IF;

    -- Add source column to identify origin (point)
    all_cols := all_cols || ', ''point'' AS source';

    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            %s
        FROM %I
        WHERE geometry IS NOT NULL%s;
    $sql$, tmp_view_name, all_cols, source, custom_filter);

    PERFORM finalize_materialized_view(
        tmp_view_name,
        target,
        array_to_string(unique_columns, ', '),
        sql_create
    );
END;
$$ LANGUAGE plpgsql;
