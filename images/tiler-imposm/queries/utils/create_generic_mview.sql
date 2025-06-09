-- ============================================================================
-- Function: create_generic_mview
-- Description:
--   Creates a materialized view from the specified input table, selecting all
--   columns (except 'geometry', 'name', 'start_date', 'end_date') along with:
--     - `osm_id`: transformed with ABS(osm_id) AS osm_id
--     - `name`: cleaned with NULLIF(name, '')
--     - `start_date`, `end_date`: cleaned with NULLIF(..., '')
--     - `start_decdate`, `end_decdate`: derived using pad_date() and 
--       isodatetodecimaldate() for temporal filtering
--     - Language-specific name columns from `languages` table
--     - `geometry`: included at the end
--
-- Parameters:
--   input_table     TEXT      - Name of the source table.
--   view_name       TEXT      - Name of the materialized view to create.
--   unique_columns  TEXT[]    - Columns used for DISTINCT ON and unique index 
--                               (default: ['osm_id']).
--
-- Notes:
--   - Uses DISTINCT ON + ORDER BY for deduplication.
--   - Geometry is indexed with GiST.
--   - Uniqueness enforced on specified unique_columns.
-- ============================================================================
DROP FUNCTION IF EXISTS create_generic_mview(TEXT, TEXT, TEXT[]);
CREATE OR REPLACE FUNCTION create_generic_mview(
  input_table TEXT,
  view_name TEXT,
  unique_columns TEXT[] DEFAULT ARRAY['osm_id']
)
RETURNS void AS $$
DECLARE
    lang_columns TEXT;
    table_columns TEXT;
    quoted_unique_cols TEXT;
    sql_create TEXT;
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
      AND table_name = input_table
      AND column_name NOT IN ('geometry', 'name', 'start_date', 'end_date');

    -- Quoted unique columns for DISTINCT ON and ORDER BY
    SELECT string_agg(quote_ident(c), ', ')
    INTO quoted_unique_cols
    FROM unnest(unique_columns) AS c;

    -- Create materialized view
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
        view_name,
        quoted_unique_cols,
        table_columns,
        lang_columns,
        input_table,
        quoted_unique_cols
    );

    RAISE NOTICE '====Creating generic materialized view from % to % ====', input_table, view_name;
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
    EXECUTE sql_create;
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE format('CREATE UNIQUE INDEX idx_%I_unique ON %I(%s);', view_name, view_name, quoted_unique_cols);

    RAISE NOTICE 'Materialized view % created successfully.', view_name;
END;
$$ LANGUAGE plpgsql;
