-- ============================================================================
-- Function: derive_centroid_mview
-- Description:
--   Creates a new materialized view with point centroids from an existing
--   materialized view containing area geometries (polygons/multipolygons).
--
--   - Converts area geometries to centroid points using ST_MaximumInscribedCircle,
--     which gives a better centroid position (center of the largest inscribed
--     circle) than ST_Centroid.
--   - If union_source is provided, performs UNION ALL with that point mview
--     (it must expose the same columns as the source mview).
--   - Deduplicates with DISTINCT ON (id, source, osm_id).
--
-- Parameters:
--   source        TEXT     - Name of the source materialized view to read from (must contain area geometries)
--   target        TEXT     - Name of the target materialized view to create/replace (will contain point geometries)
--   where_filter  TEXT     - Optional WHERE clause filter applied to the source branch
--                            (e.g., "type IN ('water', 'pond')"). NULL = no filter
--   union_source  TEXT     - Optional name of a point mview to merge via UNION ALL
--                            (must have the same columns as source). NULL = no merge
--   only_named    BOOLEAN  - When TRUE, keeps only source rows with a non-empty name
--                            or at least one non-null name_* column. Default FALSE
--   min_metric    DOUBLE PRECISION - Minimum 'area' to keep a centroid (0 = no filter).
--                            Applies to the polygon branch only; union_source rows are points.
--
-- Notes:
--   - Creates the materialized view using a temporary swap mechanism
--   - Adds a spatial index (GiST) on geometry and a unique index on (id, source, osm_id)
--   - union_source rows are filtered only by geometry IS NOT NULL
-- ============================================================================
DROP FUNCTION IF EXISTS derive_centroid_mview;

CREATE OR REPLACE FUNCTION derive_centroid_mview(
    source        TEXT,
    target        TEXT,
    where_filter  TEXT DEFAULT NULL,
    union_source  TEXT DEFAULT NULL,
    only_named    BOOLEAN DEFAULT FALSE,
    min_metric    DOUBLE PRECISION DEFAULT 0
)
RETURNS void AS $$
DECLARE
    all_cols       TEXT;
    plain_cols     TEXT;
    name_columns   TEXT;
    name_filter    TEXT := '';
    custom_filter  TEXT := '';
    area_filter    TEXT := '';
    union_query    TEXT;
    sql_create     TEXT;
    tmp_mview_name TEXT := target || '_tmp';
    unique_cols    TEXT := 'id, source, osm_id';
BEGIN
    RAISE NOTICE '==> [MVIEW CENTROID] Creating % from % (where_filter: %, union_source: %, only_named: %)', target, source, where_filter, union_source, only_named;

    -- Get ALL columns from the source mview, converting geometry to its centroid.
    -- Use pg_attribute which is more reliable for materialized views than information_schema.
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
      AND c.relname = source
      AND a.attnum > 0
      AND NOT a.attisdropped;

    IF all_cols = '' THEN
        RAISE EXCEPTION 'No columns found for %. Make sure the materialized view exists.', source;
    END IF;

    -- Plain column list (no expressions) for the outer DISTINCT ON select
    SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum)
    INTO plain_cols
    FROM pg_attribute a
    JOIN pg_class c ON a.attrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND c.relname = source
      AND a.attnum > 0
      AND NOT a.attisdropped;

    -- Build name filter: keep only rows with a name or at least one name_* column
    IF only_named THEN
        SELECT COALESCE(string_agg(
            format('%I IS NOT NULL', a.attname),
            ' OR '
        ), '')
        INTO name_columns
        FROM pg_attribute a
        JOIN pg_class c ON a.attrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public'
          AND c.relname = source
          AND a.attname LIKE 'name_%'
          AND a.attnum > 0
          AND NOT a.attisdropped;

        IF name_columns <> '' THEN
            name_filter := format(' AND ((name IS NOT NULL AND name <> '''') OR (%s))', name_columns);
        ELSE
            name_filter := ' AND (name IS NOT NULL AND name <> '''')';
        END IF;
    END IF;

    -- Build custom WHERE filter (if provided)
    IF where_filter IS NOT NULL AND length(trim(where_filter)) > 0 THEN
        custom_filter := format(' AND (%s)', where_filter);
    END IF;

    -- Build area filter (polygon branch only)
    IF min_metric > 0 THEN
        area_filter := format(' AND area >= %s', min_metric);
    END IF;

    -- Centroids branch (source mview)
    union_query := format($sql$
        SELECT %s
        FROM %I
        WHERE geometry IS NOT NULL
          AND ST_GeometryType(geometry) IN ('ST_Polygon', 'ST_MultiPolygon')
        %s%s%s
    $sql$, all_cols, source, name_filter, custom_filter, area_filter);

    -- Add UNION ALL with the point materialized view only if provided
    IF union_source IS NOT NULL THEN
        union_query := union_query || format($sql$
            UNION ALL
            SELECT %s
            FROM %I
            WHERE geometry IS NOT NULL
        $sql$, plain_cols, union_source);
    END IF;

    -- Create materialized view with DISTINCT ON to deduplicate merged rows
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT DISTINCT ON (%s) %s
        FROM (%s) AS combined
        ORDER BY %s;
    $sql$,
        tmp_mview_name,
        unique_cols,
        plain_cols,
        union_query,
        unique_cols
    );

    PERFORM finalize_materialized_view(
        tmp_mview_name,
        target,
        unique_cols,
        sql_create
    );
END;
$$ LANGUAGE plpgsql;
