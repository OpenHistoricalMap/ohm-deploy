-- ============================================================================
-- Function: create_transport_points_centroids_mview
-- Description:
--   Creates a materialized view combining:
--     - Centroids of named transport polygons (filtered by area),
--     - Named transport points directly.
--
--   Allows optional filtering by the 'type' column (via a TEXT[] array).
--   Centroids are computed using ST_MaximumInscribedCircle.
--   Multilingual columns are added using get_language_columns().
--
-- Parameters:
--   view_name  TEXT                      - Name of the materialized view to be created.
--   min_area   DOUBLE PRECISION          - Minimum polygon area (in m²) for inclusion.
--
-- Notes:
--   - Drops existing view using a temporary swap pattern.
--   - GiST spatial index on geometry.
--   - Unique index on (osm_id, type, class).
--   - Supports temporal filtering via date columns.
-- ============================================================================

DROP FUNCTION IF EXISTS create_transport_points_centroids_mview;

CREATE OR REPLACE FUNCTION create_transport_points_centroids_mview(
    view_name TEXT,
    min_area DOUBLE PRECISION DEFAULT 0
)
RETURNS void AS $$
DECLARE 
    lang_columns TEXT := get_language_columns();
    tmp_view_name TEXT := view_name || '_tmp';
    unique_columns TEXT := 'osm_id, type, class';
    sql_create TEXT;
BEGIN
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            (ST_MaximumInscribedCircle(geometry)).center AS geometry,
            ABS(osm_id) AS osm_id, 
            NULLIF(name, '') AS name, 
            class, 
            type, 
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
            ROUND(ST_Area(geometry)::numeric)::bigint AS area_m2,
            %s
        FROM osm_transport_areas
        WHERE name IS NOT NULL AND name <> '' AND ST_Area(geometry) > %L

        UNION ALL

        SELECT 
            geometry,
            ABS(osm_id) AS osm_id, 
            NULLIF(name, '') AS name, 
            class, 
            type, 
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
            NULL AS area_m2, 
            %s
        FROM osm_transport_points;
    $sql$, tmp_view_name, lang_columns, min_area, lang_columns);

    PERFORM finalize_materialized_view(
        tmp_view_name,
        view_name,
        unique_columns,
        sql_create
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Create materialized views for transport points centroids
-- ============================================================================
-- We include aerodrome to start at zoom 10 from https://github.com/OpenHistoricalMap/issues/issues/1083
SELECT create_transport_points_centroids_mview('mv_transport_points_centroids_z10_13', 0);

SELECT create_transport_points_centroids_mview('mv_transport_points_centroids_z14_20', 0);
