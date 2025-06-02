-- ============================================================================
-- Function: create_or_refresh_amenity_points_centroids_mview
-- Description:
--   This function creates or refreshes a materialized view that combines named
--   centroids from polygonal amenity areas and named amenity points into a 
--   unified layer called "amenity_points_centroids".
--
--   For amenity areas, centroids are calculated using ST_MaximumInscribedCircle,
--   and their area is included in square meters as an integer. Amenity points are
--   included directly with a NULL value for the area field.
--
-- Parameters:
--   view_name     TEXT              - The name of the materialized view to create.
--   min_area      DOUBLE PRECISION - Minimum area (in m²) to include amenity areas.
--   force_create  BOOLEAN DEFAULT FALSE - If TRUE, always recreates the view.
--
-- Notes:
--   - Only features with a non-empty "name" are included.
--   - Language-specific columns are added dynamically from the `languages` table.
--   - Geometry is indexed using GiST; uniqueness is enforced on (osm_id, type).
-- ============================================================================

DROP FUNCTION IF EXISTS create_or_refresh_amenity_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_or_refresh_amenity_points_centroids_mview(
    view_name TEXT,
    min_area DOUBLE PRECISION DEFAULT 0,
    force_create BOOLEAN DEFAULT FALSE
)
RETURNS void AS $$
DECLARE 
    sql_drop TEXT;
    sql_create TEXT;
    sql_index TEXT;
    sql_unique_index TEXT;
    lang_columns TEXT;
BEGIN
    -- Check if we need to recreate the view
    IF NOT force_create AND NOT recreate_or_refresh_view(view_name) THEN
        RETURN;
    END IF;

    RAISE NOTICE 'Creating materialized view: % with area > %', view_name, min_area;

    -- Get dynamic language columns from `languages` table
    lang_columns := get_language_columns();

    sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
    EXECUTE sql_drop;

    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            (ST_MaximumInscribedCircle(geometry)).center AS geometry,
            osm_id, 
            name, 
            type, 
            ROUND(area)::bigint AS area_m2,
            start_date, 
            end_date, 
            tags,
            %s
        FROM osm_amenity_areas
        WHERE name IS NOT NULL AND name <> '' AND area > %L

        UNION ALL

        SELECT 
            geometry,
            osm_id, 
            name, 
            type, 
            NULL AS area_m2, 
            start_date, 
            end_date,
            tags,
            %s
        FROM osm_amenity_points;
    $sql$, view_name, lang_columns, min_area, lang_columns);
    EXECUTE sql_create;

    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;

    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type);', view_name, view_name);
    EXECUTE sql_unique_index;

    RAISE NOTICE 'Materialized view % created successfully.', view_name;
END;
$$ LANGUAGE plpgsql;

SELECT create_or_refresh_amenity_points_centroids_mview('mview_amenity_points_centroids_z14_20', 0, TRUE);
