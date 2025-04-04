-- This script creates materialized views for admin boundarie centroids. 
CREATE OR REPLACE FUNCTION create_admin_boundaries_mview_centroid(
  input_table TEXT,
  mview_name TEXT
)
RETURNS void AS $$
DECLARE
  sql_drop_centroid TEXT;
  sql_create_centroid TEXT;
  sql_index_centroid TEXT;
  sql_unique_index_centroid TEXT;
BEGIN
  RAISE NOTICE '==== Creating centroid materialized view: % from table: % ====', mview_name, input_table;

  -- Drop existing materialized view if it exists
  sql_drop_centroid := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', mview_name);
  EXECUTE sql_drop_centroid;
  RAISE NOTICE 'Dropped existing view: %', mview_name;

  -- Create materialized view
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
      tags
    FROM %I
    WHERE name IS NOT NULL AND name <> ''
      AND osm_id NOT IN (SELECT osm_id FROM osm_relation_members WHERE role = 'label');
  $sql$, mview_name, input_table);
  EXECUTE sql_create_centroid;
  RAISE NOTICE 'Created materialized view: %', mview_name;

  -- Create spatial index
  sql_index_centroid := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', mview_name, mview_name);
  EXECUTE sql_index_centroid;
  RAISE NOTICE 'Created spatial index: idx_%_geom', mview_name;

  -- Create unique index on osm_id
  sql_unique_index_centroid := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_osm_id ON %I (osm_id);', mview_name, mview_name);
  EXECUTE sql_unique_index_centroid;
  RAISE NOTICE 'Created unique index: idx_%_osm_id', mview_name;

END;
$$ LANGUAGE plpgsql;

SELECT create_admin_boundaries_mview_centroid('osm_admin_areas_z0_2', 'mview_admin_boundaries_centroid_z0_2');
SELECT create_admin_boundaries_mview_centroid('osm_admin_areas_z3_5', 'mview_admin_boundaries_centroid_z3_5');
SELECT create_admin_boundaries_mview_centroid('osm_admin_areas_z6_7', 'mview_admin_boundaries_centroid_z6_7');
SELECT create_admin_boundaries_mview_centroid('osm_admin_areas_z8_9', 'mview_admin_boundaries_centroid_z8_9');
SELECT create_admin_boundaries_mview_centroid('osm_admin_areas_z10_12', 'mview_admin_boundaries_centroid_z10_12');
SELECT create_admin_boundaries_mview_centroid('osm_admin_areas_z13_15', 'mview_admin_boundaries_centroid_z13_15');
SELECT create_admin_boundaries_mview_centroid('osm_admin_areas_z16_20', 'mview_admin_boundaries_centroid_z16_20');
