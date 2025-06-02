-- ============================================================================
-- Function: create_or_refresh_landuse_points_centroids_mview
-- Description:
--   Creates or refreshes a materialized view that merges:
--     - Centroids of polygonal landuse areas using ST_MaximumInscribedCircle
--     - Landuse points directly, with area_m2 set to NULL
--
-- Parameters:
--   view_name    TEXT              - Name of the materialized view.
--   min_area     DOUBLE PRECISION  - Minimum area (in m²) to include landuse areas.
--   force_create BOOLEAN DEFAULT FALSE - If TRUE, always recreates the view.
--
-- Notes:
--   - Only includes features with non-empty "name" values.
--   - Multilingual name columns are dynamically added using the `languages` table.
--   - View is recreated if language hash changed or if force_create = TRUE.
--   - Adds GiST index on geometry and a UNIQUE index on (osm_id, type, class).
-- ============================================================================
DROP FUNCTION IF EXISTS create_or_refresh_landuse_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_or_refresh_landuse_points_centroids_mview(
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
    -- Check if we should recreate based on lang hash or force flag
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
            class, 
            start_date, 
            end_date, 
            ROUND(area)::bigint AS area_m2,
            tags,
            %s
        FROM osm_landuse_areas
        WHERE name IS NOT NULL AND name <> '' AND area > %L

        UNION ALL

        SELECT 
            geometry,
            osm_id, 
            name, 
            type, 
            class, 
            start_date, 
            end_date, 
            NULL AS area_m2, 
            tags,
            %s
        FROM osm_landuse_points;
    $sql$, view_name, lang_columns, min_area, lang_columns);
    EXECUTE sql_create;

    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;

    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type, class);', view_name, view_name);
    EXECUTE sql_unique_index;

    RAISE NOTICE 'Materialized view % created successfully.', view_name;
END;
$$ LANGUAGE plpgsql;


SELECT create_or_refresh_landuse_points_centroids_mview('mv_landuse_points_centroids_z10_11', 500, TRUE);
SELECT create_or_refresh_landuse_points_centroids_mview('mv_landuse_points_centroids_z12_13', 100, TRUE);
SELECT create_or_refresh_landuse_points_centroids_mview('mv_landuse_points_centroids_z14_20', 0, TRUE);
