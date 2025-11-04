-- ============================================================================
-- Function: prepare_points_mview
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
--   points_table       TEXT    - Name of the source points table
--   mview_name         TEXT    - Name of the final materialized view to create
--   unique_columns     TEXT    - Columns for unique index (default: 'id, source, osm_id')
--
-- Returns:
--   TEXT    - Name of the created materialized view
--
-- Notes:
--   - Creates a MATERIALIZED VIEW (not a table)
--   - Uses a temporary swap mechanism
--   - Adds a spatial index (GiST) on geometry and a unique index on unique_columns
--   - Follows the same structure as create_simplified_mview
-- ============================================================================
DROP FUNCTION IF EXISTS prepare_points_mview(TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS prepare_points_table(TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS prepare_points_table(TEXT, TEXT);

CREATE OR REPLACE FUNCTION prepare_points_mview(
    points_table TEXT,
    mview_name TEXT,
    unique_columns TEXT DEFAULT 'id, source, osm_id'
)
RETURNS TEXT AS $$
DECLARE
    lang_columns TEXT;
    sql_create TEXT;
    tmp_view_name TEXT := mview_name || '_tmp';
    all_cols TEXT;
    object_kind CHAR;
BEGIN
    
    -- Language columns will always be available
    lang_columns := get_language_columns();
    
    -- Build SQL - get all columns from points_table and add calculated ones
    -- Exclude start_decdate and end_decdate because they will be recalculated
    SELECT COALESCE(string_agg(
        CASE 
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
      AND table_name = points_table
      AND column_name NOT IN ('start_decdate', 'end_decdate');
    
    -- Always add calculated date columns
    all_cols := all_cols || ', public.isodatetodecimaldate(public.pad_date(start_date, ''start''), FALSE) AS start_decdate';
    all_cols := all_cols || ', public.isodatetodecimaldate(public.pad_date(end_date, ''end''), FALSE) AS end_decdate';
    
    -- Add area columns (NULL for points)
    all_cols := all_cols || ', NULL::numeric AS area_m2';
    all_cols := all_cols || ', NULL::numeric AS area_km2';
    
    -- Add language columns (always available)
    all_cols := all_cols || ', ' || lang_columns;
    -- Add source column to identify origin (point)
    all_cols := all_cols || ', ''point'' AS source';
    
    -- Build SQL to create temporary materialized view
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            %s
        FROM %I
        WHERE geometry IS NOT NULL;
    $sql$, tmp_view_name, all_cols, points_table);
    
    -- Use finalize_materialized_view to create the view safely and consistently
    PERFORM finalize_materialized_view(
        tmp_view_name,
        mview_name,
        unique_columns,
        sql_create
    );
    
    RETURN mview_name;
END;
$$ LANGUAGE plpgsql;
