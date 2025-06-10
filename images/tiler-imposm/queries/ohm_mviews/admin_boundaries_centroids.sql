-- ============================================================================
-- Function: create_admin_boundaries_centroids_mview
-- Description:
--   Creates a materialized view of admin boundary centroids using
--   ST_MaximumInscribedCircle from polygons in the input table.
--
-- Parameters:
--   input_table  TEXT - Source table name (e.g., osm_admin_areas_z0_2).
--   mview_name   TEXT - Name of the final materialized view to create.
--
-- Notes:
--   - Excludes boundaries with role='label' from centroid calculation.
--   - Geometry is indexed using GiST.
--   - Uniqueness is enforced on osm_id.
--   - Area is stored in square kilometers as integer.
--   - Includes multilingual name columns via get_language_columns().
--   - Creates a temporary view first and then renames it for safety.
-- ============================================================================

DROP FUNCTION IF EXISTS create_admin_boundaries_centroids_mview;
CREATE OR REPLACE FUNCTION create_admin_boundaries_centroids_mview(
  input_table TEXT,
  mview_name TEXT
)
RETURNS void AS $$
DECLARE
  tmp_mview_name TEXT := mview_name || '_tmp';
  sql_create TEXT;
  lang_columns TEXT;
BEGIN
  lang_columns := get_language_columns();

  -- Generate SQL for creating the temp materialized view
  sql_create := format($sql$
    CREATE MATERIALIZED VIEW %I AS
    SELECT
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
      );
  $sql$, tmp_mview_name, lang_columns, input_table);

  -- === LOG & EXECUTION SEQUENCE ===
  RAISE NOTICE '==> [START] Creating materialized view: % from table: %', mview_name, input_table;

  RAISE NOTICE '==> [DROP TEMP] Dropping temporary view if exists: %', tmp_mview_name;
  EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', tmp_mview_name);

  RAISE NOTICE '==> [CREATE TEMP] Creating temporary materialized view: %', tmp_mview_name;
  EXECUTE sql_create;

  RAISE NOTICE '==> [INDEX] Creating GiST index on geometry';
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', tmp_mview_name, tmp_mview_name);
  
  RAISE NOTICE '==> [INDEX] Creating UNIQUE index on (osm_id)';
  EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_osm_id ON %I (osm_id);', tmp_mview_name, tmp_mview_name);

  RAISE NOTICE '==> [DROP OLD] Dropping old materialized view: %', mview_name;
  EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', mview_name);

  RAISE NOTICE '==> [RENAME] Renaming % → %', tmp_mview_name, mview_name;
  EXECUTE format('ALTER MATERIALIZED VIEW %I RENAME TO %I;', tmp_mview_name, mview_name);

  RAISE NOTICE '==> [DONE] Materialized view % created successfully.', mview_name;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Execute force creation of all admin boundaries centroids materialized views
-- ============================================================================
SELECT create_admin_boundaries_centroids_mview('osm_admin_areas_z0_2', 'mv_admin_boundaries_centroids_z0_2');
SELECT create_admin_boundaries_centroids_mview('osm_admin_areas_z3_5', 'mv_admin_boundaries_centroids_z3_5');
SELECT create_admin_boundaries_centroids_mview('osm_admin_areas_z6_7', 'mv_admin_boundaries_centroids_z6_7');
SELECT create_admin_boundaries_centroids_mview('osm_admin_areas_z8_9', 'mv_admin_boundaries_centroids_z8_9');
SELECT create_admin_boundaries_centroids_mview('osm_admin_areas_z10_12', 'mv_admin_boundaries_centroids_z10_12');
SELECT create_admin_boundaries_centroids_mview('osm_admin_areas_z13_15', 'mv_admin_boundaries_centroids_z13_15');
SELECT create_admin_boundaries_centroids_mview('osm_admin_areas_z16_20', 'mv_admin_boundaries_centroids_z16_20');
