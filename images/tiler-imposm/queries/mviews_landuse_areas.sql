-- The script aims to create materialized views for landuse using ST_Subdivide function is used to reduce the complexity of certain geometries.

CREATE OR REPLACE FUNCTION create_landuse_subdivided_mviews(
  input_table TEXT,
  mview_name TEXT
)
RETURNS void AS $$
BEGIN
  -- Drop existing materialized view if it exists
  EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I;', mview_name);

  -- Create the materialized view
  EXECUTE format($sql$
    CREATE MATERIALIZED VIEW %I AS
    SELECT
      row_number() OVER () AS id,
      *
    FROM (
      SELECT
        ST_Subdivide((g).geom, 512) AS geometry,
        osm_id,
        name,
        type,
        class,
        start_date,
        end_date,
        area,
        tags
      FROM (
        SELECT 
          osm_id,
          name,
          type,
          class,
          start_date,
          end_date,
          tags,
          area,
          ST_Dump(ST_MakeValid(geometry)) AS g
        FROM %I
        WHERE geometry IS NOT NULL
      ) AS fixed_geoms
      WHERE GeometryType((g).geom) IN ('POLYGON', 'MULTIPOLYGON')
    ) AS final_data;
  $sql$, mview_name, input_table);

  -- Create unique index
  EXECUTE format('CREATE UNIQUE INDEX idx_%I_unique ON %I(id);', mview_name, mview_name);

  -- Create geometry index
  EXECUTE format('CREATE INDEX idx_%I_geom ON %I USING GIST (geometry);', mview_name, mview_name);

END;
$$ LANGUAGE plpgsql;

-- Create the materialized views for each zoom level
SELECT create_landuse_subdivided_mviews('osm_landuse_areas_z3_5', 'mview_landuse_areas_z3_5_subdivided');
SELECT create_landuse_subdivided_mviews('osm_landuse_areas_z6_7', 'mview_landuse_areas_z6_7_subdivided');
SELECT create_landuse_subdivided_mviews('osm_landuse_areas_z8_9', 'mview_landuse_areas_z8_9_subdivided');

-- We are giong to use same ladnuse tables for zoom=>10,osm_landuse_areas_z10_12, osm_landuse_areas_z13_15, osm_landuse_areas