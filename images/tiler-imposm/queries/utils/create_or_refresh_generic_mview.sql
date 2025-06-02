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
--
-- Behavior:
--   - Uses `get_language_columns()` to inject dynamic language-specific fields.
--   - Excludes the `geometry` column from the base column list to add it last.
--   - Skips view creation if `force_create` is FALSE and `recreate_or_refresh_view` returns FALSE.
--   - Automatically adds indexes for geometry and (if available) `osm_id`.
-- ============================================================================

DROP FUNCTION IF EXISTS create_or_refresh_generic_mview;
CREATE OR REPLACE FUNCTION create_or_refresh_generic_mview(
  input_table TEXT,
  mview_name TEXT,
  force_create BOOLEAN DEFAULT FALSE
)
RETURNS void AS $$
DECLARE
    lang_columns TEXT;    -- Holds the SQL snippet for language tag columns
    table_columns TEXT;   -- Holds column names from input_table excluding 'geometry'
    sql TEXT;             -- Final SQL statement to create the materialized view
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

    -- Build and execute the CREATE MATERIALIZED VIEW SQL
    sql := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            %s,      -- dynamic non-geometry columns from input_table
            %s,      -- dynamic language columns from `languages` table
            geometry -- geometry column explicitly added at the end
        FROM %I
        WHERE geometry IS NOT NULL;
    $sql$, mview_name, table_columns, lang_columns, input_table);

    EXECUTE sql;

    -- Create spatial GiST index on geometry column
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', mview_name, mview_name);

    -- Create unique index on osm_id if it exists
    BEGIN
        EXECUTE format('CREATE UNIQUE INDEX idx_%I_osm_id ON %I(osm_id);', mview_name, mview_name);
    EXCEPTION WHEN undefined_column THEN
        RAISE NOTICE 'osm_id not found in %, skipping unique index creation', input_table;
    END;
END;
$$ LANGUAGE plpgsql;
