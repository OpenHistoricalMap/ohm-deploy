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
--   - Drops the materialized view if it already exists.
--   - Filters polygons by name and area before calculating centroids.
--   - Adds multilingual name columns dynamically from the `languages` table.
--   - Adds GiST spatial index on geometry and unique index on (osm_id, type, class).
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
    sql_drop TEXT;
    sql_create TEXT;
    sql_index TEXT;
    sql_unique_index TEXT;
    lang_columns TEXT;
BEGIN
    RAISE NOTICE 'Creating  transport points and centroids view: %', view_name;

    lang_columns := get_language_columns();

    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);

    RAISE NOTICE 'Creating materialized view % with area > %', view_name, min_area;
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
    $sql$, view_name, lang_columns, min_area, lang_columns);
    EXECUTE sql_create;

    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type, class);', view_name, view_name);

    RAISE NOTICE 'Materialized view % created successfully.', view_name;
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

