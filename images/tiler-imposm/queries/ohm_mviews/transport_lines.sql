-- ============================================================================
-- Function: create_transport_lines_mview
-- Description:
--   Creates a materialized view that merges transport lines from two source tables:
--     - `lines_table`: individual OSM way-based transport lines.
--     - `multilines_table`: relation-based multi-line transport features.
--
--
--   Each row is uniquely identified by a hash-based `id` composed of relevant attributes.
--   Features from multi-line relations include a `member` value and are marked with
--   `source_type = 'relation'`. Way-based features have `source_type = 'way'`.
--
-- Parameters:
--   lines_table       TEXT   - Table containing way-based transport lines.
--   multilines_table  TEXT   - Table containing relation-based multi-line transport features.
--   mview_name        TEXT   - Name of the materialized view to be created.
--
-- Behavior:
--   - Drops the materialized view if it already exists.
--   - Deduplicates using DISTINCT ON (id), prioritizing the first appearance.
--   - Adds multilingual name columns dynamically from the `languages` table.
--   - Creates GiST index on geometry and unique index on (id).
--
-- Notes:
--   - Both input tables must contain `geometry`, `osm_id`, `type`, `class`, `name`,
--     and extended transport-related tags (e.g., `route`, `railway`, `aeroway`, etc.).
--   - Filtering by geometry type ensures valid line features from relations.
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
  sql_create TEXT;
BEGIN
  RAISE NOTICE 'Creating or refreshing transport lines view: %', mview_name;
  RAISE NOTICE 'Tables: {"lines": "%", "multilines": "%"}', lines_table, multilines_table;

  lang_columns := get_language_columns();

  EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', mview_name);

  sql_create := format($sql$
    CREATE MATERIALIZED VIEW %I AS
    WITH combined AS (
      SELECT
        md5(
          COALESCE(CAST(osm_id AS TEXT), '') || '_' ||
          COALESCE(type, '') || '_' ||
          COALESCE(class, '')
        ) AS id,
        ABS(osm_id) AS osm_id,
        geometry,
        type,
        class,
        NULLIF(name, '') AS name,
        tunnel,
        bridge,
        oneway,
        NULLIF(ref, '') AS ref,
        z_order,
        NULLIF(access, '') AS access,
        NULLIF(service, '') AS service,
        NULLIF(ford, '') AS ford,
        NULLIF(electrified, '') AS electrified,
        NULLIF(highspeed, '') AS highspeed,
        NULLIF(usage, '') AS usage,
        railway,
        aeroway,
        highway,
        route,
        NULLIF(start_date, '') AS start_date,
        NULLIF(end_date, '') AS end_date,
        isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
        isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
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
        ABS(osm_id) AS osm_id,
        geometry,
        type,
        class,
        NULLIF(name, '') AS name,
        tunnel,
        bridge,
        oneway,
        NULLIF(ref, '') AS ref,
        z_order,
        NULLIF(access, '') AS access,
        NULLIF(service, '') AS service,
        NULLIF(ford, '') AS ford,
        NULLIF(electrified, '') AS electrified,
        NULLIF(highspeed, '') AS highspeed,
        NULLIF(usage, '') AS usage,
        railway,
        aeroway,
        highway,
        route,
        NULLIF(start_date, '') AS start_date,
        NULLIF(end_date, '') AS end_date,
        isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
        isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
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
  
  EXECUTE sql_create;

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
