-- ============================================================================
-- Function: update_or_refresh_other_points_centroids_mview
-- Description:
--   Updates or recreates a materialized view that merges centroids of named
--   polygon features from `osm_other_areas` and points from `osm_other_points`
--   into a unified layer. It only recreates the view if the set of languages has changed.
--
-- Parameters:
--   view_name   TEXT             - The name of the materialized view to be created or refreshed.
--   min_area    DOUBLE PRECISION - Minimum polygon area (in m²) to be included.
--
-- Notes:
--   - Centroids are computed with ST_MaximumInscribedCircle for polygons.
--   - Points include NULL area to reduce tile size.
--   - Only features with non-empty "name" values are included.
--   - A GiST index is added for spatial queries.
--   - A unique index is added on (osm_id, type, class).
--   - Only regenerates view if languages hash has changed.
--   - Returns TRUE if view was recreated, FALSE if only refreshed.
-- ============================================================================
DROP FUNCTION IF EXISTS update_or_refresh_other_points_centroids_mview;
CREATE OR REPLACE FUNCTION update_or_refresh_other_points_centroids_mview(
    view_name TEXT,
    min_area DOUBLE PRECISION DEFAULT 0
)
RETURNS BOOLEAN AS $$
DECLARE
    lang_columns TEXT;
    view_exists BOOLEAN;
    lang_changed BOOLEAN;
    sql_drop TEXT;
    sql_create TEXT;
    sql_index TEXT;
    sql_unique_index TEXT;
    refresh_sql TEXT;
BEGIN
    -- Check if the materialized view exists
    SELECT EXISTS (
        SELECT 1 FROM pg_matviews WHERE matviewname = view_name
    ) INTO view_exists;

    -- Check if the language hash has changed
    SELECT insert_languages_hash_if_changed() INTO lang_changed;

    IF view_exists AND NOT lang_changed THEN
        -- Refresh only if view exists and no language changes
        refresh_sql := format('REFRESH MATERIALIZED VIEW CONCURRENTLY %I;', view_name);
        RAISE NOTICE 'No language changes. Refreshing view: %', view_name;
        EXECUTE refresh_sql;
        RETURN FALSE;
    END IF;

    -- Generate dynamic language columns
    SELECT string_agg(
        format('tags -> %L AS %I', key_name, alias),
        ', '
    ) INTO lang_columns FROM languages;

    RAISE NOTICE 'Languages changed or view does not exist. Recreating view: %', view_name;

    -- Drop view if exists
    sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
    EXECUTE sql_drop;

    -- Create materialized view
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
        FROM osm_other_areas
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
        FROM osm_other_points
    $sql$, view_name, lang_columns, min_area, lang_columns);
    EXECUTE sql_create;

    -- Create indexes
    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;

    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type, class);', view_name, view_name);
    EXECUTE sql_unique_index;

    RAISE NOTICE 'View % recreated successfully.', view_name;
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

SELECT update_or_refresh_other_points_centroids_mview('mview_other_points_centroids_z14_20', 0);
