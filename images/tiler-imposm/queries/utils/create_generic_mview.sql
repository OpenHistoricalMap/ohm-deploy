-- ============================================================================
-- Function: create_generic_mview
-- Description:
--   Creates a materialized view from the specified input table, selecting all
--   columns (except 'geometry', 'name', 'start_date', 'end_date') along with:
--     - `name`: cleaned with NULLIF(name, '')
--     - `start_date`, `end_date`: cleaned with NULLIF(..., '')
--     - `start_decdate`, `end_decdate`: derived as decimal dates using 
--        `pad_date()` and `isodatetodecimaldate()` for temporal filtering support
--     - Language-specific columns dynamically fetched from the `languages` table
--     - `geometry`: included at the end
--
-- Parameters:
--   input_table   TEXT              - Name of the source table.
--   mview_name    TEXT              - Name of the materialized view to create.
--   unique_columns TEXT[]           - Array of columns to enforce uniqueness 
--                                     (default: ['osm_id']).
--
-- Notes:
--   - DISTINCT ON + ORDER BY is used for deterministic deduplication.
--   - Geometry is indexed using GiST.
--   - Uniqueness is enforced on the specified `unique_columns`.
-- ============================================================================

DROP FUNCTION IF EXISTS create_generic_mview(TEXT, TEXT, TEXT[]);
CREATE OR REPLACE FUNCTION create_generic_mview(
  input_table TEXT,
  mview_name TEXT,
  unique_columns TEXT[] DEFAULT ARRAY['osm_id']
)
RETURNS void AS $$
DECLARE
    lang_columns TEXT;
    table_columns TEXT;
    quoted_unique_cols TEXT;
    sql TEXT;
BEGIN
    RAISE NOTICE 'Creating generic materialized view from % to %', input_table, mview_name;

    -- Get dynamic language columns from `languages` table
    lang_columns := get_language_columns();

    -- Get all columns except geometry, name, start_date, end_date
    SELECT string_agg(quote_ident(column_name), ', ')
    INTO table_columns
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = input_table
      AND column_name NOT IN ('geometry', 'name', 'start_date', 'end_date');

    -- Drop existing materialized view if it exists
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', mview_name);

    -- Quoted unique columns for DISTINCT ON and ORDER BY
    SELECT string_agg(quote_ident(c), ', ') INTO quoted_unique_cols FROM unnest(unique_columns) AS c;

    -- Create materialized view
    sql := format($sql$
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
        mview_name,
        quoted_unique_cols,
        table_columns,
        lang_columns,
        input_table,
        quoted_unique_cols
    );

    EXECUTE sql;

    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', mview_name, mview_name);
    EXECUTE format('CREATE UNIQUE INDEX idx_%I_unique ON %I(%s);', mview_name, mview_name, quoted_unique_cols);
END;
$$ LANGUAGE plpgsql;
