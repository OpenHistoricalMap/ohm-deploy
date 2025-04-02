-- This script creates materialized views for transport lines
-- it creates a materialized views for each zoom level merging transport lines and one for the multilines
CREATE OR REPLACE FUNCTION create_transport_lines_mviews(
  lines_table TEXT,
  multilines_table TEXT,
  mview_name TEXT
)
RETURNS void AS $$
DECLARE
  sql_drop TEXT;
  sql_create TEXT;
  sql_unique_index TEXT;
  sql_geometry_index TEXT;
BEGIN
  RAISE NOTICE 'Processing: {"lines": "%", "mview": "%", "multilines": "%"}', 
               lines_table, mview_name, multilines_table;

  -- Drop materialized view if it exists
  sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', mview_name);
  RAISE NOTICE 'Executing: %', sql_drop;
  EXECUTE sql_drop;

  -- Construct the SQL query to create the materialized view
  sql_create := format($sql$
    CREATE MATERIALIZED VIEW %I AS
    SELECT DISTINCT ON (osm_id, type) 
      md5(COALESCE(CAST(osm_id AS TEXT), '') || '_' || COALESCE(type, '')) AS id, 
      osm_id,
      geometry,
      type,
      name,
      tunnel,
      bridge,
      oneway,
      ref,
      z_order,
      access,
      service,
      ford,
      class,
      electrified,
      highspeed,
      usage,
      railway,
      aeroway,
      highway,
      route,
      start_date,
      end_date,
      tags,
      NULL AS member,
      'way' AS source_type
    FROM %I
    WHERE geometry IS NOT NULL

    UNION ALL

    SELECT DISTINCT ON (osm_id, type, member)
      md5(COALESCE(CAST(osm_id AS TEXT), '') || '_' || COALESCE(CAST(member AS TEXT), '') || '_' || COALESCE(type, '')) AS id,
      osm_id,
      geometry,
      type,
      name,
      tunnel,
      bridge,
      oneway,
      ref,
      z_order,
      access,
      service,
      ford,
      class,
      electrified,
      highspeed,
      usage,
      railway,
      aeroway,
      highway,
      route,
      start_date,
      end_date,
      tags,
      member,
      'relation' AS source_type
    FROM %I
    WHERE ST_GeometryType(geometry) = 'ST_LineString'
    AND geometry IS NOT NULL;
  $sql$, mview_name, lines_table, multilines_table);

  RAISE NOTICE 'Executing creation of materialized view: %', mview_name;
  EXECUTE sql_create;

  -- Create indexes
  sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_osm_id ON %I (id);', mview_name, mview_name);
  EXECUTE sql_unique_index;

  sql_geometry_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', mview_name, mview_name);
  EXECUTE sql_geometry_index;

  RAISE NOTICE 'Indexes successfully created for %', mview_name;
END;
$$ LANGUAGE plpgsql;

SELECT create_transport_lines_mviews('osm_transport_lines_z6', 'osm_transport_multilines_z6', 'mview_transport_lines_z6');
SELECT create_transport_lines_mviews('osm_transport_lines_z7', 'osm_transport_multilines_z7', 'mview_transport_lines_z7');
SELECT create_transport_lines_mviews('osm_transport_lines_z8', 'osm_transport_multilines_z8', 'mview_transport_lines_z8');
SELECT create_transport_lines_mviews('osm_transport_lines_z9', 'osm_transport_multilines_z9', 'mview_transport_lines_z9');
SELECT create_transport_lines_mviews('osm_transport_lines_z10_11', 'osm_transport_multilines_z10_11', 'mview_transport_lines_z10_11');
SELECT create_transport_lines_mviews('osm_transport_lines_z12_13', 'osm_transport_multilines_z12_13', 'mview_transport_lines_z12_13');
SELECT create_transport_lines_mviews('osm_transport_lines', 'osm_transport_multilines', 'mview_transport_lines_14_20');
