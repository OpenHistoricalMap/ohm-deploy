-- ============================================================================
-- Function: create_admin_boundaries_areas_mview
-- Description:
--   Creates a materialized view from the specified source table.
--   - Includes multilingual name columns using get_language_columns().
--   - Calculates area in km² (rounded to integer).
--   - No filtering; all rows from the source table are included.
--
-- Parameters:
--   source_table TEXT - Name of the source table to read from.
--   view_name    TEXT - Name of the materialized view to be created.
--
-- Notes:
--   - Creates the materialized view using a temporary swap mechanism to avoid downtime.
--   - Adds a spatial (GiST) index on geometry and a unique index on (osm_id, type, admin_level).
--   - Includes temporal fields: start_date, end_date, and their decimal date equivalents.
--   - Useful for rendering administrative boundaries at different zoom levels.
-- ============================================================================
DROP FUNCTION IF EXISTS create_admin_boundaries_areas_mview;

CREATE OR REPLACE FUNCTION create_admin_boundaries_areas_mview(
    source_table TEXT,
    view_name TEXT
)
RETURNS void AS $$
DECLARE 
    lang_columns TEXT := get_language_columns();
    tmp_view_name TEXT := view_name || '_tmp';
    unique_columns TEXT := 'osm_id, type, admin_level';
    sql_create TEXT;
BEGIN
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            geometry,
            ABS(osm_id) AS osm_id, 
            NULLIF(name, '') AS name, 
            type, 
            admin_level,
            ROUND(CAST(area AS numeric) / 1000000)::integer AS area_km2, 
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
            area,
            %s
        FROM %I;
    $sql$, tmp_view_name, lang_columns, source_table);

    PERFORM finalize_materialized_view(
        tmp_view_name,
        view_name,
        unique_columns,
        sql_create
    );
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- Create materialized views from osm_admin_boundaries_areas
-- ============================================================================
SELECT create_admin_boundaries_areas_mview('osm_admin_areas_z0_2', 'mv_admin_boundaries_areas_z0_2');
SELECT create_admin_boundaries_areas_mview('osm_admin_areas_z3_5', 'mv_admin_boundaries_areas_z3_5');
SELECT create_admin_boundaries_areas_mview('osm_admin_areas_z6_7', 'mv_admin_boundaries_areas_z6_7');
SELECT create_admin_boundaries_areas_mview('osm_admin_areas_z8_9', 'mv_admin_boundaries_areas_z8_9');
SELECT create_admin_boundaries_areas_mview('osm_admin_areas_z10_12', 'mv_admin_boundaries_areas_z10_12');
SELECT create_admin_boundaries_areas_mview('osm_admin_areas_z13_15', 'mv_admin_boundaries_areas_z13_15');
SELECT create_admin_boundaries_areas_mview('osm_admin_areas_z16_20', 'mv_admin_boundaries_areas_z16_20');
