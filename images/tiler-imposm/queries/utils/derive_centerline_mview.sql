-- ============================================================================
-- Function: derive_centerline_mview
-- Description:
--   Creates a materialized view with centerlines for area features, used to
--   label elongated water bodies along their shape (#1374).
--
--   - Takes all attributes (name, name_*, dates, ...) from an area mview.
--   - Replaces the polygon geometry with the line from lines_table, joined
--     by osm_id. lines_table is filled by scripts/water_centerlines.py.
--   - Keeps only named rows that have a centerline.
--   - Deduplicates with DISTINCT ON (id, source, osm_id).
--
-- Parameters:
--   source        TEXT             - Area mview to read attributes from (e.g. 'mv_water_areas_z10_12')
--   target        TEXT             - Target mview to create/replace
--   lines_table   TEXT             - Table with (osm_id, geometry) centerlines
--   simplify_tol  DOUBLE PRECISION - ST_Simplify tolerance for the line (0 = no simplification)
--
-- Notes:
--   - If lines_table is empty, the mview is created with no rows, so the tile
--     layer is empty but still exists.
-- ============================================================================
DROP FUNCTION IF EXISTS derive_centerline_mview;

CREATE OR REPLACE FUNCTION derive_centerline_mview(
    source        TEXT,
    target        TEXT,
    lines_table   TEXT DEFAULT 'water_areas_centerlines',
    simplify_tol  DOUBLE PRECISION DEFAULT 0
)
RETURNS void AS $$
DECLARE
    all_cols       TEXT;
    plain_cols     TEXT;
    geom_expr      TEXT;
    sql_create     TEXT;
    tmp_mview_name TEXT := target || '_tmp';
    unique_cols    TEXT := 'id, source, osm_id';
BEGIN
    RAISE NOTICE '==> [MVIEW CENTERLINE] Creating % from % + % (simplify_tol: %)', target, source, lines_table, simplify_tol;

    IF simplify_tol > 0 THEN
        geom_expr := format('ST_Simplify(c.geometry, %s) AS geometry', simplify_tol);
    ELSE
        geom_expr := 'c.geometry AS geometry';
    END IF;

    -- All columns from the source mview, with geometry taken from the lines table
    SELECT COALESCE(string_agg(
        CASE
            WHEN a.attname = 'geometry' THEN geom_expr
            ELSE 'a.' || quote_ident(a.attname)
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

    SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum)
    INTO plain_cols
    FROM pg_attribute a
    JOIN pg_class c ON a.attrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND c.relname = source
      AND a.attnum > 0
      AND NOT a.attisdropped;

    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT DISTINCT ON (%s) %s
        FROM (
            SELECT %s
            FROM %I a
            JOIN %I c ON c.osm_id = a.osm_id
            WHERE a.name IS NOT NULL AND a.name <> ''
        ) AS lines
        ORDER BY %s;
    $sql$,
        tmp_mview_name,
        unique_cols,
        plain_cols,
        all_cols,
        source,
        lines_table,
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
