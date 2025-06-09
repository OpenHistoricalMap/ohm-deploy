-- ============================================================================
-- Function: create_buildings_points_centroids_mview
-- Description:
--   Creates a materialized view that merges named centroids from
--   polygonal building areas and named building points into a unified layer
--   called "buildings_points_centroids".
--
--   For building areas, centroids are calculated using ST_MaximumInscribedCircle,
--   and area is stored in square meters (as integer). If available, height values
--   are sanitized (non-numeric characters removed) and cast to double precision.
--
--   Named building points are included directly, with NULL values for both 
--   height and area.
--
--   Temporal fields `start_date` and `end_date` are included as-is, and 
--   additional precalculated columns `start_decdate` and `end_decdate` 
--   are generated using the `isodatetodecimaldate` function.
--
-- Parameters:
--   view_name     TEXT              - Name of the materialized view to create.
--   min_area      DOUBLE PRECISION - Minimum area (in m²) to include building areas.
--
-- Notes:
--   - Only features with a non-empty "name" are included.
--   - Geometry is indexed using GiST.
--   - Uniqueness is enforced on the combination of (osm_id, type).
--   - Language-specific name columns are added dynamically from the `languages` table.
-- ============================================================================
DROP FUNCTION IF EXISTS create_buildings_points_centroids_mview;

CREATE OR REPLACE FUNCTION create_buildings_points_centroids_mview(
    view_name TEXT,
    min_area DOUBLE PRECISION DEFAULT 0
)
RETURNS void AS $$
DECLARE
    sql_drop TEXT;
    sql_create TEXT;
    sql_index TEXT;
    sql_unique_index TEXT;
    lang_columns TEXT;
BEGIN
    lang_columns := get_language_columns();

    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS

        SELECT
            geometry,
            osm_id,
            NULLIF(name, '') AS name,
            NULL AS height,
            NULL AS area_m2,
            type,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
            %s
        FROM osm_buildings_points
        WHERE name IS NOT NULL AND name <> ''

        UNION ALL

        SELECT
            (ST_MaximumInscribedCircle(geometry)).center AS geometry,
            osm_id,
            NULLIF(name, '') AS name,
            CASE
                WHEN height IS NULL OR trim(height) = '' THEN NULL
                ELSE regexp_replace(height, '[^0-9\.]', '', 'g')::double precision
            END AS height,
            ROUND(area)::bigint AS area_m2,
            type,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
            %s
        FROM osm_buildings
        WHERE name IS NOT NULL AND name <> '' AND area >= %L;
    $sql$, view_name, lang_columns, lang_columns, min_area);

    RAISE NOTICE '====Creating buildings points and centroids materialized view % with area > % ====', view_name, min_area;
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
    EXECUTE sql_create;
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_uid ON %I (osm_id, type);', view_name, view_name);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);

    RAISE NOTICE 'Materialized view % created successfully.', view_name;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Create materialized views for  buildings points centroids
-- ============================================================================
SELECT create_buildings_points_centroids_mview('mv_buildings_points_centroids_z14_20', 0);

-- ============================================================================
-- Create materialized views for buildings areas
-- ============================================================================
SELECT create_generic_mview( 'osm_buildings', 'mv_osm_buildings_areas_z14_20', ARRAY['osm_id', 'type']);
