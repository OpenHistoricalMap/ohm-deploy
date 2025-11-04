
-- ============================================================================
-- Function: create_centroids_mview
-- Description:
--   Creates a materialized view with centroids from a polygons materialized view
--   and optionally merges with a points materialized view.
--   
--   - Converts polygon geometries to centroid points using ST_MaximumInscribedCircle
--   - If points_mview is provided, performs UNION ALL (points_mview must have the same columns)
--
-- Parameters:
--   polygons_mview   TEXT    - Name of the source polygons materialized view
--   mview_name       TEXT    - Name of the materialized view to create
--   points_mview     TEXT    - Optional name of the points materialized view (must already have the same columns as polygons_mview)
--
-- Notes:
--   - Extracts all columns from polygons_mview and converts geometry to centroid
--   - points_mview must be prepared beforehand with prepare_points_mview() (with the same columns as polygons_mview)
--   - Only converts polygons to centroids and merges with points
-- ============================================================================
DROP FUNCTION IF EXISTS create_centroids_mview(TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS create_centroids_mview(TEXT, TEXT);

-- Function with all parameters (polygons, mview_name, optional points)
CREATE OR REPLACE FUNCTION create_centroids_mview(
    polygons_mview TEXT,
    mview_name TEXT,
    points_mview TEXT DEFAULT NULL
)
RETURNS void AS $$
DECLARE
    sql_create TEXT;
    union_query TEXT;
    tmp_mview_name TEXT := mview_name || '_tmp';
    all_cols TEXT;
    quoted_unique_cols TEXT;
    name_filter TEXT;
    name_columns TEXT;
BEGIN
    -- Get ALL columns from polygons_mview (which comes from create_simplified_mview)
    -- Use pg_attribute which is more reliable for materialized views than information_schema
    SELECT COALESCE(string_agg(
        CASE 
            WHEN a.attname = 'geometry' THEN '(ST_MaximumInscribedCircle(geometry)).center AS geometry'
            ELSE quote_ident(a.attname)
        END,
        ', ' ORDER BY a.attnum
    ), '')
    INTO all_cols
    FROM pg_attribute a
    JOIN pg_class c ON a.attrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND c.relname = polygons_mview
      AND a.attnum > 0
      AND NOT a.attisdropped;

    -- Get all name_* columns to build filter condition
    SELECT COALESCE(string_agg(
        format('%I IS NOT NULL', a.attname),
        ' OR '
    ), '')
    INTO name_columns
    FROM pg_attribute a
    JOIN pg_class c ON a.attrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND c.relname = polygons_mview
      AND a.attname LIKE 'name_%'
      AND a.attnum > 0
      AND NOT a.attisdropped;

    -- Build name filter: must have name OR at least one name_* column
    IF name_columns IS NOT NULL AND name_columns <> '' THEN
        name_filter := format('AND ((name IS NOT NULL AND name <> '''') OR (%s))', name_columns);
    ELSE
        name_filter := 'AND (name IS NOT NULL AND name <> '''')';
    END IF;

    -- Use id, source and osm_id for DISTINCT ON (will always exist in polygons_mview and points_mview)
    quoted_unique_cols := 'id, source, osm_id';

    -- Build areas query (centroids) - only include polygons with names
    union_query := format($sql$
        SELECT %s
        FROM %I
        WHERE geometry IS NOT NULL
        %s
    $sql$, all_cols, polygons_mview, name_filter);
    
    -- Add UNION ALL with points materialized view only if provided
    IF points_mview IS NOT NULL THEN
        union_query := union_query || format($sql$
            UNION ALL
            SELECT %s
            FROM %I
            WHERE geometry IS NOT NULL
        $sql$, all_cols, points_mview);
    END IF;
    
    -- Optimization: Enable parallelization before creating the view
    -- This helps speed up ST_MaximumInscribedCircle using multiple workers
    -- PERFORM set_config('max_parallel_workers_per_gather', '4', true);
    -- PERFORM set_config('enable_parallel_hash', 'on', true);
    -- PERFORM set_config('enable_parallel_append', 'on', true);
    
    -- Create materialized view with DISTINCT ON
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT DISTINCT ON (%s) *
        FROM (%s) AS combined
        ORDER BY %s;
    $sql$,
        tmp_mview_name,
        quoted_unique_cols,
        union_query,
        quoted_unique_cols
    );
    
    PERFORM finalize_materialized_view(
        tmp_mview_name,
        mview_name,
        quoted_unique_cols,
        sql_create
    );
END;
$$ LANGUAGE plpgsql;
