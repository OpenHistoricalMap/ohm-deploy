-- ============================================================================
-- Function: create_transport_points_centroids_mview
-- Description:
--   Creates a materialized view that merges centroids of transport area polygons
--   and transport points into a single unified layer for rendering.
--
--   - Centroids are calculated using ST_MaximumInscribedCircle for named polygonal features.
--   - Points are included directly with NULL as area to optimize vector tile size.
--
-- Parameters:
--   view_name  TEXT              - Name of the materialized view to be created.
--   min_area   DOUBLE PRECISION - Minimum area (in m²) to include polygonal features.
--
-- Behavior:
--   - Drops and replaces the view using a temporary view to avoid downtime.
--   - Filters polygons by name and area before calculating centroids.
--   - Adds multilingual name columns dynamically from the `languages` table.
--   - Creates GiST spatial index on geometry and unique index on (osm_id, type, class).
--
-- Notes:
--   - Useful for rendering transport-related labels and icons at mid/high zoom levels.
--   - Supports time-based filtering with `start_date`, `end_date`, and derived decimal dates.
-- ============================================================================

DROP FUNCTION IF EXISTS create_transport_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_transport_points_centroids_mview(
    view_name TEXT,
    min_area DOUBLE PRECISION DEFAULT 0
)
RETURNS void AS $$
DECLARE 
    lang_columns TEXT;
    sql_create TEXT;
    tmp_view_name TEXT := view_name || '_tmp';
BEGIN
    lang_columns := get_language_columns();

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
            isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
            ROUND(area)::bigint AS area_m2,
            tags,
            %s
        FROM osm_transport_areas
        WHERE name IS NOT NULL AND name <> '' AND area > %L

        UNION ALL

        SELECT 
            geometry,
            ABS(osm_id) AS osm_id, 
            NULLIF(name, '') AS name, 
            class, 
            type, 
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
            NULL AS area_m2, 
            tags,
            %s
        FROM osm_transport_points;
    $sql$, tmp_view_name, lang_columns, min_area, lang_columns);

    -- === LOG & EXECUTION SEQUENCE ===
    RAISE NOTICE '==> [START] Creating transport points and centroids view: % (tmp: %)', view_name, tmp_view_name;

    RAISE NOTICE '==> [DROP TEMP] Dropping temporary view if exists: %', tmp_view_name;
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', tmp_view_name);

    RAISE NOTICE '==> [CREATE TEMP] Creating temporary materialized view: %', tmp_view_name;
    EXECUTE sql_create;

    RAISE NOTICE '==> [INDEX] Creating GiST index on geometry';
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', tmp_view_name, tmp_view_name);

    RAISE NOTICE '==> [INDEX] Creating UNIQUE index on (osm_id, type, class)';
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type, class);', tmp_view_name, tmp_view_name);

    RAISE NOTICE '==> [DROP OLD] Dropping old view if exists: %', view_name;
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);

    RAISE NOTICE '==> [RENAME] Renaming % → %', tmp_view_name, view_name;
    EXECUTE format('ALTER MATERIALIZED VIEW %I RENAME TO %I;', tmp_view_name, view_name);

    RAISE NOTICE '==> [DONE] Materialized view % created successfully.', view_name;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Create materialized views for transport areas
-- ============================================================================
SELECT create_generic_mview('osm_transport_areas', 'mv_transport_areas_z12_20', ARRAY['osm_id', 'type', 'class']);

-- ============================================================================
-- Create materialized views for transport points centroids
-- ============================================================================
SELECT create_transport_points_centroids_mview('mv_transport_points_centroids_z14_20', 0);

