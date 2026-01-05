-- ============================================================================
-- Function: create_admin_boundaries_centroids_mview
-- Description:
--   Creates a materialized view of admin boundary centroids using
--   ST_MaximumInscribedCircle from polygons in the input table.
--
-- Parameters:
--   input_table   TEXT - Source table name (e.g., osm_admin_areas).
--   mview_name    TEXT - Name of the final materialized view to create.
--   unique_columns TEXT - Comma-separated list of columns for uniqueness
--                        (default: 'id, osm_id, type').
--   where_filter   TEXT - Optional WHERE filter condition to apply
--                        (e.g., 'admin_level IN (1,2)').
--
-- Notes:
--   - Excludes boundaries with role='label' from centroid calculation.
--   - Area is stored in square kilometers as integer.
--   - Geometry is indexed using GiST.
--   - Uniqueness is enforced on the specified unique_columns.
--   - Includes multilingual name columns via get_language_columns().
--   - Uses finalize_materialized_view() for atomic creation and renaming.
-- ============================================================================

DROP FUNCTION IF EXISTS create_admin_boundaries_centroids_mview;
CREATE OR REPLACE FUNCTION create_admin_boundaries_centroids_mview(
  input_table TEXT,
  mview_name TEXT,
  unique_columns TEXT DEFAULT 'id, osm_id, type',
  where_filter TEXT DEFAULT NULL
)
RETURNS void AS $$
DECLARE
  tmp_mview_name TEXT := mview_name || '_tmp';
  sql_create TEXT;
  lang_columns TEXT := get_language_columns();
  custom_filter TEXT;
BEGIN
  -- Build custom WHERE filter (if provided)
  -- Note: custom_filter includes leading space and AND, so it can be concatenated directly
  IF where_filter IS NOT NULL AND where_filter <> '' THEN
    custom_filter := format(' AND (%s)', where_filter);
  ELSE
    custom_filter := '';
  END IF;

  sql_create := format($sql$
    CREATE MATERIALIZED VIEW %I AS
    SELECT
      ABS(osm_id) AS id,
      osm_id,
      NULLIF(name, '') AS name,
      admin_level,
      NULLIF(type, '') AS type,
      (ST_MaximumInscribedCircle(geometry)).center AS geometry,
      NULLIF(start_date, '') AS start_date,
      NULLIF(end_date, '') AS end_date,
      isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
      isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
      ROUND(CAST(area AS numeric) / 1000000)::integer AS area_km2,
      %s
    FROM %I
    WHERE name IS NOT NULL AND name <> ''
      AND osm_id NOT IN (
        SELECT osm_id FROM osm_relation_members WHERE role = 'label'
      )%s;
  $sql$, tmp_mview_name, lang_columns, input_table, custom_filter);

  -- Finalize the materialized view and its indexes
  PERFORM finalize_materialized_view(
    tmp_mview_name,
    mview_name,
    unique_columns,
    sql_create
  );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Execute force creation of all admin boundaries centroids materialized views
-- ============================================================================
SELECT create_admin_boundaries_centroids_mview('osm_admin_areas', 'mv_admin_boundaries_centroids_z0_2', 'id, osm_id, type', 'admin_level IN (1,2)');
SELECT create_admin_boundaries_centroids_mview('osm_admin_areas', 'mv_admin_boundaries_centroids_z3_5', 'id, osm_id, type', 'admin_level IN (1,2,3,4)');
SELECT create_admin_boundaries_centroids_mview('osm_admin_areas', 'mv_admin_boundaries_centroids_z6_7', 'id, osm_id, type', 'admin_level IN (1,2,3,4,5,6)');
SELECT create_admin_boundaries_centroids_mview('osm_admin_areas', 'mv_admin_boundaries_centroids_z8_9', 'id, osm_id, type', 'admin_level IN (1,2,3,4,5,6,7,8,9)');
SELECT create_admin_boundaries_centroids_mview('osm_admin_areas', 'mv_admin_boundaries_centroids_z10_12', 'id, osm_id, type', 'admin_level IN (1,2,3,4,5,6,7,8,9,10)');
SELECT create_admin_boundaries_centroids_mview('osm_admin_areas', 'mv_admin_boundaries_centroids_z13_15', 'id, osm_id, type', 'admin_level IN (1,2,3,4,5,6,7,8,9,10,11)');
SELECT create_admin_boundaries_centroids_mview('osm_admin_areas', 'mv_admin_boundaries_centroids_z16_20', 'id, osm_id, type', 'admin_level IN (1,2,3,4,5,6,7,8,9,10,11)');
