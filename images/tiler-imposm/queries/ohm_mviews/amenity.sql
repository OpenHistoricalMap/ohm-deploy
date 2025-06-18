-- ============================================================================
-- Function: create_amenity_points_centroids_mview
-- Description:
--   Creates a materialized view that merges named centroids from
--   polygonal amenity areas and named amenity points into a unified layer
--   called "amenity_points_centroids".
--
--   For amenity areas, centroids are calculated using ST_MaximumInscribedCircle,
--   and area is stored in square meters (as integer). Amenity points are included
--   directly, with NULL values for the area field.
--
--   Temporal fields `start_date` and `end_date` are included as-is, and 
--   additional precalculated columns `start_decdate` and `end_decdate` 
--   are generated using the `isodatetodecimaldate` function.
--
--   This function uses finalize_materialized_view for consistent creation,
--   indexing, and renaming steps.
--
-- Parameters:
--   view_name     TEXT              - Name of the materialized view to create.
--   min_area      DOUBLE PRECISION - Minimum area (in m²) to include amenity areas.
--
-- Notes:
--   - Only features with a non-empty "name" are included.
--   - Geometry is indexed using GiST.
--   - Uniqueness is enforced on the combination of (osm_id, type).
--   - Language-specific name columns are added dynamically from the `languages` table.
-- ============================================================================

DROP FUNCTION IF EXISTS create_amenity_points_centroids_mview;

CREATE OR REPLACE FUNCTION create_amenity_points_centroids_mview(
    view_name TEXT,
    min_area DOUBLE PRECISION DEFAULT 0
)
RETURNS void AS $$
DECLARE 
    tmp_view_name TEXT := view_name || '_tmp';
    sql_create TEXT;
    lang_columns TEXT := get_language_columns();
    unique_columns TEXT := 'osm_id, type';
BEGIN

    sql_create := format(
        $sql$ 
        CREATE MATERIALIZED VIEW %I AS
        SELECT 
            (ST_MaximumInscribedCircle(geometry)).center AS geometry,
            osm_id,
            NULLIF(name, '') AS name,
            type,
            ROUND(area)::bigint AS area_m2,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
            %s
        FROM osm_amenity_areas
        WHERE name IS NOT NULL AND name <> '' AND area > %L

        UNION ALL

        SELECT 
            geometry,
            osm_id,
            NULLIF(name, '') AS name,
            type,
            NULL AS area_m2,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
            %s
        FROM osm_amenity_points;
        $sql$,
        tmp_view_name,
        lang_columns,
        min_area,
        lang_columns
    );

    PERFORM finalize_materialized_view(
        tmp_view_name,
        view_name,
        unique_columns,
        sql_create
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Create materialized view for amenity points centroids
-- ============================================================================
SELECT create_amenity_points_centroids_mview('mv_amenity_points_centroids_z14_20', 0);

-- ============================================================================
-- Create materialized view for amenity areas
-- ============================================================================
SELECT create_generic_mview( 'osm_amenity_areas', 'mv_amenity_areas_z14_20', ARRAY ['osm_id', 'type']);
