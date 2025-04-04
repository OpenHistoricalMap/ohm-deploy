CREATE OR REPLACE FUNCTION create_other_areas_mviews(
  source_table TEXT,
  mview_name TEXT,
  min_area DOUBLE PRECISION
)
RETURNS VOID AS $$
BEGIN
  RAISE NOTICE 'Creating materialized view % with area > %', mview_name, min_area;

  EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I;', mview_name);

  EXECUTE format($sql$
    CREATE MATERIALIZED VIEW %I AS
    SELECT
      id,
      osm_id,
      geometry,
      name,
      class,
      type,
      area,
      NULLIF(start_date, '') AS start_date,
      NULLIF(end_date, '') AS end_date,
      isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
      isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
      tags
    FROM %I
    WHERE area > %L
      AND geometry IS NOT NULL;
  $sql$, mview_name, source_table, min_area);

  EXECUTE format('CREATE UNIQUE INDEX idx_%I_id ON %I (id);', mview_name, mview_name);
  EXECUTE format('CREATE INDEX idx_%I_geom ON %I USING GIST (geometry);', mview_name, mview_name);

  RAISE NOTICE 'Materialized view % created.', mview_name;
END;
$$ LANGUAGE plpgsql;

SELECT create_other_areas_mviews('osm_other_areas', 'mview_other_areas_z6_8', 1000000);
SELECT create_other_areas_mviews('osm_other_areas', 'mview_other_areas_z9_11', 100000);
SELECT create_other_areas_mviews('osm_other_areas', 'mview_other_areas_z12_14', 10000);