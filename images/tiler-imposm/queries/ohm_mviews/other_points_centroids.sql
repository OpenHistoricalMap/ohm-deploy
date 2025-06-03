-- ============================================================================
-- Function: create_or_refresh_other_points_centroids_mview
-- Description:
--   Creates or refreshes a materialized view combining:
--     - Centroids of polygon features from `osm_other_areas`, and
--     - Point features from `osm_other_points`.
--   The result is a unified layer of named features for rendering and labeling.
--
--   It will:
--     - Refresh the view if the set of languages has not changed.
--     - Recreate the view from scratch if the set of languages has changed
--       or if `force_create` is set to TRUE.
--
-- Parameters:
--   view_name     TEXT             - Name of the materialized view.
--   min_area      DOUBLE PRECISION - Minimum area (in m²) for polygons to be included.
--   force_create  BOOLEAN          - If TRUE, always recreates the view.
--
-- Notes:
--   - Uses `ST_MaximumInscribedCircle` to compute polygon centroids.
--   - Only includes features with non-empty "name" values.
--   - Multilingual name columns are dynamically added from `languages` table.
--   - Spatial and unique indexes are created to optimize rendering and queries.
-- ============================================================================

DROP FUNCTION IF EXISTS create_or_refresh_other_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_or_refresh_other_points_centroids_mview(
  view_name TEXT,
  min_area DOUBLE PRECISION DEFAULT 0,
  force_create BOOLEAN DEFAULT FALSE
)
RETURNS BOOLEAN AS $$
DECLARE
  lang_columns TEXT;
  sql_drop TEXT;
  sql_create TEXT;
  sql_index TEXT;
  sql_unique_index TEXT;
BEGIN
  -- Check if we should recreate or refresh the view
  IF NOT force_create AND NOT refresh_mview(view_name) THEN
    RETURN FALSE;
  END IF;

  RAISE NOTICE 'Creating or refreshing view: %', view_name;

  -- Get dynamic language columns
  lang_columns := get_language_columns();

  -- Drop the existing materialized view
  sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
  EXECUTE sql_drop;

  -- Create the new materialized view with centroids and multilingual name tags
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
    FROM osm_other_points;
  $sql$, view_name, lang_columns, min_area, lang_columns);
  EXECUTE sql_create;

  -- Create spatial index
  sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
  EXECUTE sql_index;

  -- Create unique index
  sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type, class);', view_name, view_name);
  EXECUTE sql_unique_index;

  RAISE NOTICE 'View % recreated successfully.', view_name;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

SELECT create_or_refresh_other_points_centroids_mview('mv_other_points_centroids_z14_20', 0, TRUE);
