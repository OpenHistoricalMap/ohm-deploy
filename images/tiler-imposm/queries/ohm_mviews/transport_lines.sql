-- ============================================================================
-- Function: create_transport_lines_mview
-- Description:
--   creates  materialized view that merges transport lines and multi-lines
--   into one unified layer for rendering, including multilingual name tags.
--
-- Parameters:
--   lines_table       TEXT    - Table with individual transport lines.
--   multilines_table  TEXT    - Table with multi-line transport features.
--   mview_name        TEXT    - Name of the materialized view to create or refresh.
--
-- Notes:
--   - Uses DISTINCT ON to deduplicate by (osm_id, type[, member]).
--   - Language columns are dynamically generated from the `languages` table.
--   - If force_create is FALSE, the function checks whether language hash or view state changed.
--   - Creates spatial (GiST) and unique indexes.
-- ============================================================================
DROP FUNCTION IF EXISTS create_transport_lines_mview;
CREATE OR REPLACE FUNCTION create_transport_lines_mview(
  lines_table TEXT,
  multilines_table TEXT,
  mview_name TEXT
)
RETURNS void AS $$
DECLARE
  lang_columns TEXT;
  sql TEXT;
BEGIN
  RAISE NOTICE 'Creating or refreshing transport lines view: %', mview_name;
  RAISE NOTICE 'Tables: {"lines": "%", "multilines": "%"}', lines_table, multilines_table;

  lang_columns := get_language_columns();

  EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', mview_name);

  sql := format($sql$
    CREATE MATERIALIZED VIEW %I AS
    WITH combined AS (
      SELECT
        md5(
          COALESCE(CAST(osm_id AS TEXT), '') || '_' ||
          COALESCE(type, '') || '_' ||
          COALESCE(class, '')
        ) AS id,
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

      SELECT
        md5(
          COALESCE(CAST(osm_id AS TEXT), '') || '_' ||
          COALESCE(CAST(member AS TEXT), '') || '_' ||
          COALESCE(type, '') || '_' ||
          COALESCE(class, '')
        ) AS id,
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
        AND geometry IS NOT NULL
    )
    SELECT DISTINCT ON (id) *
    FROM combined;
  $sql$, mview_name, lang_columns, lines_table, lang_columns, multilines_table);
  
  EXECUTE sql;

  EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I(id);', mview_name, mview_name);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST(geometry);', mview_name, mview_name);

  RAISE NOTICE 'Materialized view % created and indexed.', mview_name;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Create materialized views for  transport lines
-- ============================================================================
SELECT create_transport_lines_mview('osm_transport_lines_z5', 'osm_transport_multilines_z5', 'mv_transport_lines_z5');
SELECT create_transport_lines_mview('osm_transport_lines_z6', 'osm_transport_multilines_z6', 'mv_transport_lines_z6');
SELECT create_transport_lines_mview('osm_transport_lines_z7', 'osm_transport_multilines_z7', 'mv_transport_lines_z7');
SELECT create_transport_lines_mview('osm_transport_lines_z8', 'osm_transport_multilines_z8', 'mv_transport_lines_z8');
SELECT create_transport_lines_mview('osm_transport_lines_z9', 'osm_transport_multilines_z9', 'mv_transport_lines_z9');
SELECT create_transport_lines_mview('osm_transport_lines_z10_11', 'osm_transport_multilines_z10_11', 'mv_transport_lines_z10_11');
SELECT create_transport_lines_mview('osm_transport_lines_z12_13', 'osm_transport_multilines_z12_13', 'mv_transport_lines_z12_13');
SELECT create_transport_lines_mview('osm_transport_lines', 'osm_transport_multilines', 'mv_transport_lines_z14_20');
