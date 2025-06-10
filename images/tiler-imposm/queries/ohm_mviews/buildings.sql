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
    tmp_view_name TEXT := view_name || '_tmp';
    sql_create TEXT;
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
            isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
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
            isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
            %s
        FROM osm_buildings
        WHERE name IS NOT NULL AND name <> '' AND area >= %L;
    $sql$, tmp_view_name, lang_columns, lang_columns, min_area);

    -- === LOG & EXECUTION SEQUENCE ===
    RAISE NOTICE '==> [START] Creating buildings centroids view: % (area > %)', view_name, min_area;

    RAISE NOTICE '==> [DROP TEMP] Dropping temporary view if exists: %', tmp_view_name;
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', tmp_view_name);

    RAISE NOTICE '==> [CREATE TEMP] Creating temporary materialized view: %', tmp_view_name;
    EXECUTE sql_create;

    RAISE NOTICE '==> [INDEX] Creating UNIQUE index on (osm_id, type)';
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_uid ON %I (osm_id, type);', tmp_view_name, tmp_view_name);

    RAISE NOTICE '==> [INDEX] Creating GiST index on geometry';
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', tmp_view_name, tmp_view_name);

    RAISE NOTICE '==> [DROP OLD] Dropping old view if exists: %', view_name;
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);

    RAISE NOTICE '==> [RENAME] Renaming % → %', tmp_view_name, view_name;
    EXECUTE format('ALTER MATERIALIZED VIEW %I RENAME TO %I;', tmp_view_name, view_name);

    RAISE NOTICE '==> [DONE] Materialized view % created successfully.', view_name;
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
