-- ============================================================================
-- Function: create_or_refresh_admin_boundaries_centroids_mview
-- Description:
--   Creates or refreshes a materialized view of admin boundary centroids using
--   ST_MaximumInscribedCircle from polygons in the given input table.
--
-- Parameters:
--   input_table  TEXT             - Source table name (e.g., osm_admin_areas_z0_2).
--   mview_name   TEXT             - Name of the materialized view to create.
--   force_create BOOLEAN DEFAULT FALSE - Forces recreation even if language hash hasn't changed.
--
-- Notes:
--   - Excludes boundaries with role='label' from centroid calculation.
--   - Geometry is indexed using GiST; uniqueness is enforced on osm_id.
--   - Area is stored in square kilometers as numeric(10,1).
--   - Includes multilingual name columns using `get_language_columns()`.
-- ============================================================================

DROP FUNCTION IF EXISTS create_or_refresh_admin_boundaries_centroids_mview;
CREATE OR REPLACE FUNCTION create_or_refresh_admin_boundaries_centroids_mview(
  input_table TEXT,
  mview_name TEXT,
  force_create BOOLEAN DEFAULT FALSE
)
RETURNS void AS $$
DECLARE
  sql_drop_centroid TEXT;
  sql_create_centroid TEXT;
  sql_index_centroid TEXT;
  sql_unique_index_centroid TEXT;
  lang_columns TEXT;
BEGIN
  -- Skip recreation if not forced and no language change
  IF NOT force_create AND NOT refresh_mview(mview_name) THEN
    RETURN;
  END IF;

  -- Get multilingual columns from `languages` table
  lang_columns := get_language_columns();

  RAISE NOTICE '==== Creating centroid materialized view: % from table: % ====', mview_name, input_table;

  sql_drop_centroid := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', mview_name);
  EXECUTE sql_drop_centroid;

  sql_create_centroid := format($sql$
    CREATE MATERIALIZED VIEW %I AS
    SELECT
      osm_id,
      name,
      admin_level,
      type,
      (ST_MaximumInscribedCircle(geometry)).center AS geometry,
      start_date,
      end_date,
      ROUND(CAST(area AS numeric) / 1000000, 1)::numeric(10,1) AS area_km2,
      tags,
      %s
    FROM %I
    WHERE name IS NOT NULL AND name <> ''
      AND osm_id NOT IN (
        SELECT osm_id FROM osm_relation_members WHERE role = 'label'
      );
  $sql$, mview_name, lang_columns, input_table);
  EXECUTE sql_create_centroid;

  sql_index_centroid := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', mview_name, mview_name);
  EXECUTE sql_index_centroid;

  sql_unique_index_centroid := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_osm_id ON %I (osm_id);', mview_name, mview_name);
  EXECUTE sql_unique_index_centroid;

  RAISE NOTICE 'Materialized view % created successfully.', mview_name;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- Function: refresh_all_admin_boundaries_centroids
-- ============================================================================
DROP FUNCTION IF EXISTS refresh_all_admin_boundaries_centroids;
CREATE OR REPLACE FUNCTION refresh_all_admin_boundaries_centroids(force_create BOOLEAN DEFAULT FALSE)
RETURNS void AS $$
BEGIN
  PERFORM create_or_refresh_admin_boundaries_centroids_mview('osm_admin_areas_z0_2', 'mv_admin_boundaries_centroids_z0_2', force_create);
  PERFORM create_or_refresh_admin_boundaries_centroids_mview('osm_admin_areas_z3_5', 'mv_admin_boundaries_centroids_z3_5', force_create);
  PERFORM create_or_refresh_admin_boundaries_centroids_mview('osm_admin_areas_z6_7', 'mv_admin_boundaries_centroids_z6_7', force_create);
  PERFORM create_or_refresh_admin_boundaries_centroids_mview('osm_admin_areas_z8_9', 'mv_admin_boundaries_centroids_z8_9', force_create);
  PERFORM create_or_refresh_admin_boundaries_centroids_mview('osm_admin_areas_z10_12', 'mv_admin_boundaries_centroids_z10_12', force_create);
  PERFORM create_or_refresh_admin_boundaries_centroids_mview('osm_admin_areas_z13_15', 'mv_admin_boundaries_centroids_z13_15', force_create);
  PERFORM create_or_refresh_admin_boundaries_centroids_mview('osm_admin_areas_z16_20', 'mv_admin_boundaries_centroids_z16_20', force_create);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Execute force creation of all admin boundaries centroids materialized views
-- ============================================================================
SELECT refresh_all_admin_boundaries_centroids(TRUE); 
