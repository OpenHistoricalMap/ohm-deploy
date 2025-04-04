CREATE OR REPLACE FUNCTION create_other_areas_centroids_mviews(
  source_table TEXT,
  mview_name TEXT,
  min_area DOUBLE PRECISION DEFAULT 0
)
RETURNS VOID AS $$
BEGIN
  RAISE NOTICE 'Creating materialized view % with centroids and area > %', mview_name, min_area;
  EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I;', mview_name);

  EXECUTE format($sql$
    CREATE MATERIALIZED VIEW %I AS
    SELECT 
      id,
      osm_id,
      (ST_MaximumInscribedCircle(geometry)).center AS geometry,
      name,
      class,
      type,
      area,
      start_date,
      end_date,
      tags
    FROM %I
    WHERE 
      geometry IS NOT NULL
      AND name IS NOT NULL
      AND name <> ''
      AND area > %L;
  $sql$, mview_name, source_table, min_area);

  EXECUTE format('CREATE UNIQUE INDEX idx_%I_id ON %I (id);', mview_name, mview_name);
  EXECUTE format('CREATE INDEX idx_%I_geom ON %I USING GIST (geometry);', mview_name, mview_name);

  RAISE NOTICE 'Materialized view % created.', mview_name;
END;
$$ LANGUAGE plpgsql;

SELECT create_other_areas_centroids_mviews('osm_other_areas', 'mview_other_areas_centroids_z6_8', 1000000);
SELECT create_other_areas_centroids_mviews('osm_other_areas', 'mview_other_areas_centroids_z9_11', 100000);
SELECT create_other_areas_centroids_mviews('osm_other_areas', 'mview_other_areas_centroids_z12_14', 10000);
SELECT create_other_areas_centroids_mviews('osm_other_areas', 'mview_other_areas_centroids_z15_20');
