-- ============================================================================
-- Function: create_other_points_centroids_mview
-- Description:
--   Creates a materialized view combining:
--     - Centroids of polygonal features from `osm_other_areas`, and
--     - Point features from `osm_other_points`.
--   The result is a unified layer of named features for rendering and labeling.
--
--   For polygonal features, centroids are computed using ST_MaximumInscribedCircle,
--   and their area is included in square meters (`area_m2` as integer).
--   For point features, `area_m2` is set to NULL.
--
--   Temporal fields `start_date` and `end_date` are included as-is, and
--   additional precalculated columns `start_decdate` and `end_decdate` are 
--   generated using the `isodatetodecimaldate` function to support fast 
--   temporal filtering.
--
-- Parameters:
--   view_name     TEXT              - Name of the materialized view to create.
--   min_area      DOUBLE PRECISION - Minimum area (in m²) to include polygon features.
--
-- Notes:
--   - Only includes features with non-empty "name" values.
--   - Language-specific name columns are added dynamically using the `languages` table.
--   - Geometry is indexed using GiST.
--   - Uniqueness is enforced on the combination of (osm_id, type, class).
--   - Uses finalize_materialized_view() for atomic creation and renaming.
-- ============================================================================

DROP FUNCTION IF EXISTS create_other_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_other_points_centroids_mview(
  view_name TEXT,
  min_area DOUBLE PRECISION DEFAULT 0
)
RETURNS void AS $$
DECLARE
  lang_columns TEXT := get_language_columns();
  tmp_view_name TEXT := view_name || '_tmp';
  sql_create TEXT;
  unique_columns TEXT := 'osm_id, type, class';
BEGIN
  sql_create := format($sql$
    CREATE MATERIALIZED VIEW %I AS
    SELECT
      (ST_MaximumInscribedCircle(geometry)).center AS geometry,
      osm_id, 
      NULLIF(name, '') AS name, 
      type, 
      class, 
      NULLIF(start_date, '') AS start_date,
      NULLIF(end_date, '') AS end_date,
      isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
      isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
      ROUND(area)::bigint AS area_m2, 
      %s
    FROM osm_other_areas
    WHERE name IS NOT NULL AND name <> '' AND area > %L

    UNION ALL

    SELECT 
      geometry,
      osm_id, 
      NULLIF(name, '') AS name, 
      type, 
      class, 
      NULLIF(start_date, '') AS start_date,
      NULLIF(end_date, '') AS end_date,
      isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
      isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
      NULL AS area_m2, 
      %s
    FROM osm_other_points;
  $sql$, tmp_view_name, lang_columns, min_area, lang_columns);

  PERFORM finalize_materialized_view(
    tmp_view_name,
    view_name,
    unique_columns,
    sql_create
  );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Create materialized views for other points centroids
-- ============================================================================
SELECT create_other_points_centroids_mview('mv_other_points_centroids_z14_20', 0);

-- ============================================================================
-- Create materialized views for other areas
-- ============================================================================
SELECT create_generic_mview('osm_other_areas', 'mv_other_areas_z14_20', ARRAY['osm_id', 'type', 'class']);

-- ============================================================================
-- Create materialized views for other lines
-- ============================================================================
SELECT create_generic_mview('osm_other_lines', 'mv_other_lines_z14_20', ARRAY['osm_id', 'type', 'class']);
