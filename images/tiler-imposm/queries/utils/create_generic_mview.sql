-- ============================================================================
-- Function: create_generic_mview
-- Description:
--   Creates a materialized view from the specified source table using a temporary
--   intermediate view, and finalizes it through the finalize_materialized_view
--   procedure. It includes:
--     - All columns from the source table except geometry, name, start_date, end_date.
--     - `osm_id` transformed as ABS(osm_id) AS osm_id.
--     - `name`, `start_date`, `end_date` cleaned with NULLIF(..., '').
--     - `start_decdate`, `end_decdate` derived using pad_date() and isodatetodecimaldate().
--     - Language-specific name columns appended via get_language_columns().
--     - `geometry` column preserved at the end.
--
-- Parameters:
--   source          TEXT    - Name of the source table.
--   target          TEXT    - Name of the materialized view to create.
--   unique_columns  TEXT[]  - Columns used for DISTINCT ON and unique index (default: ARRAY['osm_id']).
--
-- Notes:
--   - Deduplication uses DISTINCT ON and ORDER BY with provided unique_columns.
--   - GiST index is created on geometry.
--   - Unique index is created on the unique_columns set.
--   - View creation is safe and atomic via temporary view, validated, indexed,
--     and renamed to final name using finalize_materialized_view().
-- ============================================================================
-- Legacy signature (pre-standardization, issue #1372)
DROP FUNCTION IF EXISTS create_generic_mview(TEXT, TEXT, TEXT[]);

CREATE OR REPLACE FUNCTION create_generic_mview(
    source          TEXT,
    target          TEXT,
    unique_columns  TEXT[] DEFAULT ARRAY['osm_id']
)
RETURNS void AS $$
DECLARE
    lang_columns TEXT;
    table_columns TEXT;
    quoted_unique_cols TEXT;
    sql_create TEXT;
    tmp_mview_name TEXT := target || '_tmp';
BEGIN
    lang_columns := get_language_columns();

    -- Build list of columns, replacing 'osm_id' with ABS(osm_id) AS osm_id
    SELECT string_agg(
        CASE
            WHEN column_name = 'osm_id' THEN 'ABS(osm_id) AS osm_id'
            ELSE quote_ident(column_name)
        END,
        ', '
    )
    INTO table_columns
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = source
      AND column_name NOT IN ('geometry', 'name', 'start_date', 'end_date');

    -- Quoted unique columns for DISTINCT ON and ORDER BY
    SELECT string_agg(quote_ident(c), ', ')
    INTO quoted_unique_cols
    FROM unnest(unique_columns) AS c;

    -- Generate SQL for creating the materialized view
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT DISTINCT ON (%s)
            %s,
            NULLIF(name, '') AS name,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            public.isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
            public.isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
            %s,
            geometry
        FROM %I
        WHERE geometry IS NOT NULL
        ORDER BY %s;
    $sql$,
        tmp_mview_name,
        quoted_unique_cols,
        table_columns,
        lang_columns,
        source,
        quoted_unique_cols
    );

    -- Use shared finalization routine
    PERFORM finalize_materialized_view(
        tmp_mview_name,
        target,
        array_to_string(unique_columns, ', '),
        sql_create
    );
END;
$$ LANGUAGE plpgsql;
