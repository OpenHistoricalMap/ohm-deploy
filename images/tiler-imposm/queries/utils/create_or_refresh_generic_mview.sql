-- ============================================================================
-- Function: create_or_refresh_generic_mview
-- Description:
--   General-purpose function to create materialized views from any table with
--   geospatial data. It dynamically selects all non-geometry columns,
--   appends dynamic language columns from the `languages` table,
--   and includes the `geometry` column at the end.
--
-- Parameters:
--   input_table   TEXT     - Source table to build the materialized view from.
--   mview_name    TEXT     - Name of the materialized view to be created.
--   force_create  BOOLEAN  - If TRUE, forcibly recreates the view even if unchanged.
--   unique_columns TEXT[]  - Array of column names to use for the unique index.
--
-- Behavior:
--   - Uses `get_language_columns()` to inject dynamic language-specific fields.
--   - Excludes the `geometry` column from the base column list to add it last.
--   - Skips view creation if `force_create` is FALSE and `recreate_or_refresh_view` returns FALSE.
--   - Automatically adds indexes for geometry and a composite unique index based on input columns.
-- ============================================================================


DROP FUNCTION IF EXISTS create_or_refresh_generic_mview(TEXT, TEXT, BOOLEAN, TEXT[]);

CREATE OR REPLACE FUNCTION create_or_refresh_generic_mview(
  input_table TEXT,
  mview_name TEXT,
  force_create BOOLEAN DEFAULT FALSE,
  unique_columns TEXT[] DEFAULT ARRAY['osm_id']
)
RETURNS void AS $$
DECLARE
    lang_columns TEXT;
    table_columns TEXT;
    quoted_unique_cols TEXT;
    sql TEXT;
BEGIN
    -- Check if we should recreate or refresh the view
    IF NOT force_create AND NOT recreate_or_refresh_view(mview_name) THEN
        RETURN;
    END IF;

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

    -- Create the materialized view
    sql := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            %s,
            %s,
            geometry
        FROM %I
        WHERE geometry IS NOT NULL;
    $sql$, mview_name, table_columns, lang_columns, input_table);
    EXECUTE sql;

    -- Create spatial GiST index
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', mview_name, mview_name);

    -- Attempt to create a composite unique index
    BEGIN
        SELECT string_agg(quote_ident(c), ', ') INTO quoted_unique_cols FROM unnest(unique_columns) AS c;
        EXECUTE format('CREATE UNIQUE INDEX idx_%I_unique ON %I(%s);', mview_name, mview_name, quoted_unique_cols);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Skipping unique index creation on view %, due to error: %', mview_name, SQLERRM;
    END;
END;
$$ LANGUAGE plpgsql;

