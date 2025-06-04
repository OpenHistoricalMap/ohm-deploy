-- ============================================================================
-- Function: create_generic_mview
-- Description:
--   General-purpose function to create materialized views from any table with
--   geospatial data. It dynamically selects all non-geometry columns,
--   appends dynamic language columns from the `languages` table,
--   and includes the `geometry` column at the end.
--
-- Parameters:
--   input_table     TEXT     - Source table to build the materialized view from.
--   mview_name      TEXT     - Name of the materialized view to be created.
--   unique_columns  TEXT[]   - Array of column names to use for DISTINCT ON and unique index.
--
-- Behavior:
--   - Uses `get_language_columns()` to inject dynamic language-specific fields.
--   - Excludes the `geometry` column from the base column list to add it last.
--   - Always recreates the view.
--   - Uses DISTINCT ON + ORDER BY to avoid duplicates based on `unique_columns`.
--   - Automatically adds spatial index and a composite unique index.
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

    -- Get all column names from the input table except 'geometry'
    SELECT string_agg(quote_ident(column_name), ', ')
    INTO table_columns
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = input_table
      AND column_name <> 'geometry';

    -- Drop existing materialized view if it exists
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', mview_name);

    -- Construct quoted column list for DISTINCT ON and ORDER BY
    SELECT string_agg(quote_ident(c), ', ') INTO quoted_unique_cols FROM unnest(unique_columns) AS c;

    -- Create the materialized view with DISTINCT ON + ORDER BY to ensure deterministic results
    sql := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT DISTINCT ON (%s)
            %s,
            %s,
            geometry
        FROM %I
        WHERE geometry IS NOT NULL
        ORDER BY %s;
    $sql$, mview_name, quoted_unique_cols, table_columns, lang_columns, input_table, quoted_unique_cols);
    EXECUTE sql;

    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', mview_name, mview_name);
    EXECUTE format('CREATE UNIQUE INDEX idx_%I_unique ON %I(%s);', mview_name, mview_name, quoted_unique_cols);

END;
$$ LANGUAGE plpgsql;
