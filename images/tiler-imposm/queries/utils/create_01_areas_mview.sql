-- ============================================================================
-- Function: create_areas_mview
-- Description:
--   Creates a materialized view from a source table with configurable geometry
--   simplification and minimum area filtering.
--
--   - Applies ST_SimplifyPreserveTopology for geometry simplification
--   - Filters by minimum area (in square meters)
--   - Includes area_m2 (rounded area in m²) and area_km2 (rounded area in km²)
--   - Includes multilingual name columns using get_language_columns()
--   - Includes temporal fields: start_date, end_date, and their decimal equivalents
--
-- Parameters:
--   source_table    TEXT              - Name of the source table or materialized view
--   view_name       TEXT              - Name of the materialized view to create
--   simplify_tol    DOUBLE PRECISION  - Simplification tolerance (0 = no simplification)
--   min_area        DOUBLE PRECISION  - Minimum area in m² to include (0 = no filter)
--   unique_columns  TEXT              - Comma-separated columns for unique index (default: 'id, osm_id, type')
--
-- Notes:
--   - Creates the materialized view using a temporary swap mechanism
--   - Adds a spatial index (GiST) on geometry and a unique index on unique_columns
--   - Useful for creating views at different zoom levels with variable simplification
-- ============================================================================
DROP FUNCTION IF EXISTS create_areas_mview(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT);

CREATE OR REPLACE FUNCTION create_areas_mview(
    source_table TEXT,
    view_name TEXT,
    simplify_tol DOUBLE PRECISION DEFAULT 0,
    min_area DOUBLE PRECISION DEFAULT 0,
    unique_columns TEXT DEFAULT 'id, osm_id, type'
)
RETURNS void AS $$
DECLARE 
    lang_columns TEXT;
    tmp_view_name TEXT := view_name || '_tmp';
    sql_create TEXT;
    simplify_expr TEXT;
    area_filter TEXT;
    all_cols TEXT;
BEGIN
    -- Language columns will always be available
    lang_columns := get_language_columns();
    
    -- Build simplification expression
    IF simplify_tol > 0 THEN
        simplify_expr := format('ST_SimplifyPreserveTopology(geometry, %s)', simplify_tol);
    ELSE
        simplify_expr := 'geometry';
    END IF;
    
    -- Build area filter
    IF min_area > 0 THEN
        area_filter := format('AND ST_Area(geometry) > %s', min_area);
    ELSE
        area_filter := '';
    END IF;
    
    -- Build SQL - get all columns from source table and replace geometry, handle special columns
    -- Exclude start_decdate and end_decdate because they will be recalculated
    SELECT COALESCE(string_agg(
        CASE 
            WHEN column_name = 'geometry' THEN format('%s AS geometry', simplify_expr)
            WHEN column_name = 'area' THEN format(
                '%I, ROUND(CAST(%I AS numeric), 1)::numeric(20,1) AS area_m2, ROUND(CAST(%I AS numeric) / 1000000, 1)::numeric(20,1) AS area_km2',
                column_name, column_name, column_name
            )
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
      AND table_name = source_table
      AND column_name NOT IN ('start_decdate', 'end_decdate');
    
    -- Always add calculated date columns
    all_cols := all_cols || ', public.isodatetodecimaldate(public.pad_date(start_date, ''start''), FALSE) AS start_decdate';
    all_cols := all_cols || ', public.isodatetodecimaldate(public.pad_date(end_date, ''end''), FALSE) AS end_decdate';
    
    -- Add language columns (always available)
    all_cols := all_cols || ', ' || lang_columns;
    -- Add source column to identify origin (polygon)
    all_cols := all_cols || ', ''polygon'' AS source';

    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            %s
        FROM %I
        WHERE geometry IS NOT NULL
        %s;
    $sql$, tmp_view_name, all_cols, source_table, area_filter);

    PERFORM finalize_materialized_view(
        tmp_view_name,
        view_name,
        unique_columns,
        sql_create
    );
END;
$$ LANGUAGE plpgsql;
