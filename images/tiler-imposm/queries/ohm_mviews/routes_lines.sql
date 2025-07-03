-- ================================================
-- Function: create_route_lines_mview
-- Description:
--   Creates a materialized view merging route lines
--   from osm_route_multilines and osm_routes_lines.
--   Supports filtering by route types and geometry simplification.
--
-- Parameters:
--   view_name (TEXT): Name of the materialized view to create.
--   allowed_types_routes (TEXT[]): Array of route types to include.
--       If NULL or contains '*', includes all route types.
--   tolerance (DOUBLE PRECISION): Simplification tolerance (map units).
--       0 = no simplification.
--
-- Returns:
--   void
-- ================================================

DROP FUNCTION IF EXISTS create_route_lines_mview;

CREATE OR REPLACE FUNCTION create_route_lines_mview(
    view_name TEXT,
    allowed_types_routes TEXT[] DEFAULT NULL,
    tolerance DOUBLE PRECISION DEFAULT 0
)
RETURNS void AS $$
DECLARE
    tmp_view_name TEXT := view_name || '_tmp';
    lang_columns TEXT := get_language_columns();
    type_filter_routes TEXT := 'TRUE';
    sql_create TEXT;
    unique_columns TEXT := 'id, osm_id, type';
BEGIN
    -- Build type filter
    IF allowed_types_routes IS NULL OR allowed_types_routes @> ARRAY['*'] THEN
        type_filter_routes := 'TRUE';
    ELSE
        type_filter_routes := format('type = ANY (%L)', allowed_types_routes);
    END IF;

    -- Generate SQL for creating the materialized view
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            CASE
                WHEN %L > 0 THEN ST_Simplify(geometry, %L)
                ELSE geometry
            END AS geometry,
            id,
            ABS(osm_id) AS osm_id,
            NULLIF(name, '') AS name,
            type,
            NULLIF(route, '') AS route,
            NULLIF(ref, '') AS ref,
            NULLIF(network, '') AS network,
            NULLIF(direction, '') AS direction,
            NULLIF(operator, '') AS operator,
            tags->'state' AS state,
            tags->'symbol' AS symbol,
            tags->'roundtrip' AS roundtrip,
            tags->'interval' AS interval,
            tags->'duration' AS duration,
            tags->'tourism' AS tourism,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
            %s
        FROM osm_route_multilines
        WHERE %s

        UNION ALL

        SELECT
            CASE
                WHEN %L > 0 THEN ST_Simplify(geometry, %L)
                ELSE geometry
            END AS geometry,
            id,
            ABS(osm_id) AS osm_id,
            NULLIF(name, '') AS name,
            type,
            NULLIF(route, '') AS route,
            NULLIF(ref, '') AS ref,
            NULLIF(network, '') AS network,
            NULLIF(direction, '') AS direction,
            NULLIF(operator, '') AS operator,
            tags->'state' AS state,
            tags->'symbol' AS symbol,
            tags->'roundtrip' AS roundtrip,
            tags->'interval' AS interval,
            tags->'duration' AS duration,
            tags->'tourism' AS tourism,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
            %s
        FROM osm_route_lines
        WHERE %s;
    $sql$, tmp_view_name,
         tolerance, tolerance, lang_columns, type_filter_routes,
         tolerance, tolerance, lang_columns, type_filter_routes);

    -- Finalize materialized view (swap tmp with actual view)
    PERFORM finalize_materialized_view(
        tmp_view_name,
        view_name,
        unique_columns,
        sql_create
    );
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- Create materialized views for route
-- ============================================================================

SELECT create_route_lines_mview('mv_route_lines_z5', ARRAY['*'], 200);
SELECT create_route_lines_mview('mv_route_lines_z6', ARRAY['*'], 150);
SELECT create_route_lines_mview('mv_route_lines_z7', ARRAY['*'], 100);
SELECT create_route_lines_mview('mv_route_lines_z8', ARRAY['*'], 50);
SELECT create_route_lines_mview('mv_route_lines_z9', ARRAY['*'], 25);
SELECT create_route_lines_mview('mv_route_lines_z10_11', ARRAY['*'], 15);
SELECT create_route_lines_mview('mv_route_lines_z12_13', ARRAY['*'], 5);
SELECT create_route_lines_mview('mv_route_lines_z14_20', ARRAY['*'], 0);
