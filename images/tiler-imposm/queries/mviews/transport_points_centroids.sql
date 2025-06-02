-- ============================================================================
-- Function: create_or_refresh_transport_points_centroids_mview
-- Description:
--   This function creates or refreshes a materialized view that merges transport area centroids 
--   (calculated from polygons) and transport points into a unified layer.
--
-- Parameters:
--   view_name     TEXT              - The name of the materialized view to create.
--   min_area      DOUBLE PRECISION - The minimum area (in m²) to include transport areas.
--   force_create  BOOLEAN DEFAULT FALSE - Forces recreation even if language hash hasn't changed.
--
-- Notes:
--   - Centroids use ST_MaximumInscribedCircle for polygonal geometries.
--   - Points are included directly with NULL area_m2 to reduce vector tile size.
--   - Only area features with non-empty "name" are included.
--   - Multilingual tags are dynamically included from the `languages` table.
--   - Geometry is indexed using GiST; uniqueness enforced on (osm_id, type, class).
-- ============================================================================

DROP FUNCTION IF EXISTS create_or_refresh_transport_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_or_refresh_transport_points_centroids_mview(
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
    -- Skip if not forced and no language/hash change
    IF NOT force_create AND NOT refresh_mview(view_name) THEN
        RETURN;
    END IF;

    -- Get dynamic language columns from `languages` table
    lang_columns := get_language_columns();

    RAISE NOTICE 'Dropping materialized view %', view_name;
    sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
    EXECUTE sql_drop;

    RAISE NOTICE 'Creating materialized view % with area > %', view_name, min_area;
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            (ST_MaximumInscribedCircle(geometry)).center AS geometry,
            osm_id, 
            name, 
            class, 
            type, 
            start_date, 
            end_date, 
            ROUND(area)::bigint AS area_m2,
            tags,
            %s
        FROM osm_transport_areas
        WHERE name IS NOT NULL AND name <> '' AND area > %L

        UNION ALL

        SELECT 
            geometry,
            osm_id, 
            name, 
            class, 
            type, 
            start_date, 
            end_date, 
            NULL AS area_m2, 
            tags,
            %s
        FROM osm_transport_points;
    $sql$, view_name, lang_columns, min_area, lang_columns);
    EXECUTE sql_create;

    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;

    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type, class);', view_name, view_name);
    EXECUTE sql_unique_index;

    RAISE NOTICE 'Materialized view % created successfully.', view_name;
END;
$$ LANGUAGE plpgsql;

SELECT create_or_refresh_transport_points_centroids_mview('mv_transport_points_centroids_z14_20', 0, TRUE);