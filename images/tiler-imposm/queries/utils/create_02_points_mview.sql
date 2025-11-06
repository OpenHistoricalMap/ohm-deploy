-- ============================================================================
-- Function: create_points_mview
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
--   extra_columns      TEXT[]  - Optional array of SQL expressions to add to the SELECT clause.
--                                - Each expression must include 'AS column_name' at the end
--                                - Example: 'CASE WHEN tags->''height'' IS NULL OR trim(tags->''height'') = '''' THEN NULL WHEN trim(regexp_replace(tags->''height'', ''[^0-9\.]'', '''', ''g'')) = '''' THEN NULL ELSE regexp_replace(tags->''height'', ''[^0-9\.]'', '''', ''g'')::double precision END AS height'
--                                - Use double single quotes ('') inside expressions for string literals
--                                - Expressions are used as-is, no automatic generation
--
-- Returns:
--   TEXT    - Name of the created materialized view
--
-- Notes:
--   - Creates a MATERIALIZED VIEW (not a table)
--   - Uses a temporary swap mechanism
--   - Adds a spatial index (GiST) on geometry and a unique index on unique_columns
--   - Follows the same structure as create_simplified_mview
--   - extra_columns: All expressions are used exactly as provided, must include 'AS column_name'
--   - Columns specified in extra_columns will be excluded from the source table to avoid duplicates
-- ============================================================================
DROP FUNCTION IF EXISTS create_points_mview(TEXT, TEXT, TEXT, TEXT[]);

CREATE OR REPLACE FUNCTION create_points_mview(
    points_table TEXT,
    mview_name TEXT,
    unique_columns TEXT DEFAULT 'id, source, osm_id',
    extra_columns TEXT[] DEFAULT NULL
)
RETURNS TEXT AS $$
DECLARE
    lang_columns TEXT;
    sql_create TEXT;
    tmp_view_name TEXT := mview_name || '_tmp';
    all_cols TEXT;
    object_kind CHAR;
    columns_to_add TEXT := '';
    col_expr TEXT;
    columns_to_exclude TEXT[] := ARRAY['start_decdate', 'end_decdate', 'area', 'area_m2', 'area_km2'];
    col_name TEXT;
    as_pos INTEGER;
BEGIN
    
    -- Language columns will always be available
    lang_columns := get_language_columns();
    
    -- Extract column names from extra_columns expressions to exclude them from source table
    -- This prevents "column specified more than once" errors
    IF extra_columns IS NOT NULL AND array_length(extra_columns, 1) > 0 THEN
        FOREACH col_expr IN ARRAY extra_columns
        LOOP
            -- Extract column name from expression (look for "AS column_name" or "as column_name")
            as_pos := position(' AS ' IN upper(col_expr));
            IF as_pos > 0 THEN
                col_name := trim(substring(col_expr FROM as_pos + 4));
                -- Remove any trailing whitespace or SQL keywords
                col_name := regexp_replace(col_name, '\s+.*$', '');
                col_name := lower(col_name);
                -- Add to exclusion list if not already present
                IF NOT (col_name = ANY(columns_to_exclude)) THEN
                    columns_to_exclude := array_append(columns_to_exclude, col_name);
                END IF;
            END IF;
        END LOOP;
    END IF;
    
    -- Build SQL - get all columns from points_table and add calculated ones
    -- Exclude start_decdate, end_decdate, area columns, and any columns from extra_columns
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
      AND column_name != ALL(columns_to_exclude);
    
    -- Always add calculated date columns
    all_cols := all_cols || ', public.isodatetodecimaldate(public.pad_date(start_date, ''start''), FALSE) AS start_decdate';
    all_cols := all_cols || ', public.isodatetodecimaldate(public.pad_date(end_date, ''end''), FALSE) AS end_decdate';
    
    -- Add area columns (NULL for points) - must match create_simplified_mview structure
    all_cols := all_cols || ', NULL::numeric AS area';
    all_cols := all_cols || ', NULL::numeric AS area_m2';
    all_cols := all_cols || ', NULL::numeric AS area_km2';
    
    -- Add language columns (always available)
    all_cols := all_cols || ', ' || lang_columns;
    
    -- Add extra columns from expressions if provided
    -- All expressions are used as-is, must include 'AS column_name'
    IF extra_columns IS NOT NULL AND array_length(extra_columns, 1) > 0 THEN
        FOREACH col_expr IN ARRAY extra_columns
        LOOP
            -- Use expression exactly as provided, add comma separator
            IF columns_to_add <> '' THEN
                columns_to_add := columns_to_add || ', ';
            END IF;
            columns_to_add := columns_to_add || col_expr;
        END LOOP;
    END IF;
    
    -- Add extra columns if any were provided
    IF columns_to_add <> '' THEN
        all_cols := all_cols || ', ' || columns_to_add;
    END IF;

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
