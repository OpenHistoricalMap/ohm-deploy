/**
layers: admin_boundaries_centroids
tegola_config: config/providers/admin_boundaries_centroids.toml
filters_per_zoom_level:
- z16-20: mv_admin_boundaries_centroids_z16_20 | filter=(all from parent mv_admin_boundaries_areas_z16_20)
- z13-15: mv_admin_boundaries_centroids_z13_15 | filter=(all from parent mv_admin_boundaries_areas_z13_15)
- z10-12: mv_admin_boundaries_centroids_z10_12 | filter=(all from parent mv_admin_boundaries_areas_z10_12)
- z8-9:   mv_admin_boundaries_centroids_z8_9   | filter=(all from parent mv_admin_boundaries_areas_z8_9)
- z6-7:   mv_admin_boundaries_centroids_z6_7   | filter=(all from parent mv_admin_boundaries_areas_z6_7)
- z3-5:   mv_admin_boundaries_centroids_z3_5   | filter=(all from parent mv_admin_boundaries_areas_z3_5)
- z0-2:   mv_admin_boundaries_centroids_z0_2   | filter=(all from parent mv_admin_boundaries_areas_z0_2)

## description:
OpenhistoricalMap admin boundaries centroids, contains point representations of administrative boundaries (centroids from polygons) for labeling

## details:
- Only features with names are included
- Excludes boundaries with role='label' from relation members
- Created from admin boundary areas using ST_MaximumInscribedCircle to calculate centroids
**/

-- ============================================================================
-- Function: create_admin_boundaries_centroids_mview
-- Description:
--   Creates a materialized view of admin boundary centroids using
--   ST_MaximumInscribedCircle from polygons in the input materialized view.
--   Extracts all columns dynamically from the source materialized view and
--   converts the geometry to a centroid point.
--
-- Parameters:
--   source_mview  TEXT - Source materialized view name (e.g., mv_admin_boundaries_areas_z16_20).
--   mview_name    TEXT - Name of the final materialized view to create.
--   unique_columns TEXT - Comma-separated list of columns for uniqueness
--                        (default: 'id, osm_id, type').
--   where_filter   TEXT - Optional WHERE filter condition to apply
--                        (e.g., 'admin_level IN (1,2)').
--
-- Notes:
--   - Excludes boundaries with role='label' from centroid calculation.
--   - Extracts all columns dynamically from the source materialized view.
--   - Converts geometry to centroid using ST_MaximumInscribedCircle.
--   - Geometry is indexed using GiST.
--   - Uniqueness is enforced on the specified unique_columns.
--   - Uses finalize_materialized_view() for atomic creation and renaming.
-- ============================================================================

DROP FUNCTION IF EXISTS create_admin_boundaries_centroids_mview;
CREATE OR REPLACE FUNCTION create_admin_boundaries_centroids_mview(
  source_mview TEXT,
  mview_name TEXT,
  unique_columns TEXT DEFAULT 'id, osm_id, type',
  where_filter TEXT DEFAULT NULL
)
RETURNS void AS $$
DECLARE
  tmp_mview_name TEXT := mview_name || '_tmp';
  sql_create TEXT;
  all_cols TEXT;
  custom_filter TEXT;
BEGIN
  -- Build custom WHERE filter (if provided)
  -- Note: custom_filter includes leading space and AND, so it can be concatenated directly
  IF where_filter IS NOT NULL AND where_filter <> '' THEN
    custom_filter := format(' AND (%s)', where_filter);
  ELSE
    custom_filter := '';
  END IF;

  -- Get all columns from the source materialized view, replacing geometry with centroid
  SELECT COALESCE(string_agg(
    CASE 
      WHEN a.attname = 'geometry' THEN '(ST_MaximumInscribedCircle(geometry)).center AS geometry'
      ELSE quote_ident(a.attname)
    END,
    ', ' ORDER BY a.attnum
  ), '')
  INTO all_cols
  FROM pg_attribute a
  JOIN pg_class c ON a.attrelid = c.oid
  JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname = 'public'
    AND c.relname = source_mview
    AND a.attnum > 0
    AND NOT a.attisdropped;

  IF all_cols IS NULL THEN
    RAISE EXCEPTION 'No columns found for %. Make sure the materialized view exists.', source_mview;
  END IF;

  sql_create := format($sql$
    CREATE MATERIALIZED VIEW %I AS
    SELECT
      %s
    FROM %I
    WHERE name IS NOT NULL AND name <> ''
      AND osm_id NOT IN (
        SELECT osm_id FROM osm_relation_members WHERE role = 'label'
      )%s;
  $sql$, tmp_mview_name, all_cols, source_mview, custom_filter);

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
-- Create centroids from corresponding area materialized views
-- The where_filter is no longer needed as the area views already have the appropriate filters
SELECT create_admin_boundaries_centroids_mview('mv_admin_boundaries_areas_z0_2', 'mv_admin_boundaries_centroids_z0_2', 'id, osm_id, type', NULL);
SELECT create_admin_boundaries_centroids_mview('mv_admin_boundaries_areas_z3_5', 'mv_admin_boundaries_centroids_z3_5', 'id, osm_id, type', NULL);
SELECT create_admin_boundaries_centroids_mview('mv_admin_boundaries_areas_z6_7', 'mv_admin_boundaries_centroids_z6_7', 'id, osm_id, type', NULL);
SELECT create_admin_boundaries_centroids_mview('mv_admin_boundaries_areas_z8_9', 'mv_admin_boundaries_centroids_z8_9', 'id, osm_id, type', NULL);
SELECT create_admin_boundaries_centroids_mview('mv_admin_boundaries_areas_z10_12', 'mv_admin_boundaries_centroids_z10_12', 'id, osm_id, type', NULL);
SELECT create_admin_boundaries_centroids_mview('mv_admin_boundaries_areas_z13_15', 'mv_admin_boundaries_centroids_z13_15', 'id, osm_id, type', NULL);
SELECT create_admin_boundaries_centroids_mview('mv_admin_boundaries_areas_z16_20', 'mv_admin_boundaries_centroids_z16_20', 'id, osm_id, type', NULL);

-- Refresh centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_centroids_z0_2;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_centroids_z3_5;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_centroids_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_centroids_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_centroids_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_centroids_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_centroids_z16_20;


