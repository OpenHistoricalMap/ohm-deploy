-- ============================================================================
-- Function: create_or_refresh_transport_lines_mview
-- Description:
--   Creates or refreshes a materialized view that merges transport lines and multi-lines
--   into one unified layer for rendering, including multilingual name tags.
--
-- Parameters:
--   lines_table       TEXT    - Table with individual transport lines.
--   multilines_table  TEXT    - Table with multi-line transport features.
--   mview_name        TEXT    - Name of the materialized view to create or refresh.
--   force_create      BOOLEAN - If TRUE, always recreates the view.
--
-- Notes:
--   - Uses DISTINCT ON to deduplicate by (osm_id, type[, member]).
--   - Language columns are dynamically generated from the `languages` table.
--   - If force_create is FALSE, the function checks whether language hash or view state changed.
--   - Creates spatial (GiST) and unique indexes.
-- ============================================================================

DROP FUNCTION IF EXISTS create_or_refresh_transport_lines_mview;
CREATE OR REPLACE FUNCTION create_or_refresh_transport_lines_mview(
  lines_table TEXT,
  multilines_table TEXT,
  mview_name TEXT,
  force_create BOOLEAN DEFAULT FALSE
)
RETURNS void AS $$
DECLARE
  lang_columns TEXT;
  sql_drop TEXT;
  sql_create TEXT;
  sql_unique_index TEXT;
  sql_geometry_index TEXT;
BEGIN
  -- Skip recreation if not forced and not needed
  IF NOT force_create AND NOT refresh_mview(mview_name) THEN
    RETURN;
  END IF;

  RAISE NOTICE 'Creating or refreshing transport lines view: %', mview_name;
  RAISE NOTICE 'Tables: {"lines": "%", "multilines": "%"}', lines_table, multilines_table;

  -- Get dynamic language columns from `languages` table
  lang_columns := get_language_columns();

  -- Drop existing view
  sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', mview_name);
  EXECUTE sql_drop;

  -- Create new materialized view
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
      'way' AS source_type,
      %s
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
      'relation' AS source_type,
      %s
    FROM %I
    WHERE ST_GeometryType(geometry) = 'ST_LineString'
      AND geometry IS NOT NULL;
  $sql$, mview_name, lang_columns, lines_table, lang_columns, multilines_table);
  EXECUTE sql_create;

  -- Indexes
  sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_osm_id ON %I (id);', mview_name, mview_name);
  EXECUTE sql_unique_index;

  sql_geometry_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', mview_name, mview_name);
  EXECUTE sql_geometry_index;

  RAISE NOTICE 'Materialized view % created and indexed.', mview_name;
END;
$$ LANGUAGE plpgsql;

SELECT create_or_refresh_transport_lines_mview('osm_transport_lines_z5', 'osm_transport_multilines_z5', 'mv_transport_lines_z5', TRUE);
SELECT create_or_refresh_transport_lines_mview('osm_transport_lines_z6', 'osm_transport_multilines_z6', 'mv_transport_lines_z6', TRUE);
SELECT create_or_refresh_transport_lines_mview('osm_transport_lines_z7', 'osm_transport_multilines_z7', 'mv_transport_lines_z7', TRUE);
SELECT create_or_refresh_transport_lines_mview('osm_transport_lines_z8', 'osm_transport_multilines_z8', 'mv_transport_lines_z8', TRUE);
SELECT create_or_refresh_transport_lines_mview('osm_transport_lines_z9', 'osm_transport_multilines_z9', 'mv_transport_lines_z9', TRUE);
SELECT create_or_refresh_transport_lines_mview('osm_transport_lines_z10_11', 'osm_transport_multilines_z10_11', 'mv_transport_lines_z10_11', TRUE);
SELECT create_or_refresh_transport_lines_mview('osm_transport_lines_z12_13', 'osm_transport_multilines_z12_13', 'mv_transport_lines_z12_13', TRUE);
SELECT create_or_refresh_transport_lines_mview('osm_transport_lines', 'osm_transport_multilines', 'mv_transport_lines_z14_20', TRUE);
