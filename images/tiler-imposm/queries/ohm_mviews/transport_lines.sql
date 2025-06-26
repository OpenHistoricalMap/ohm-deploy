-- ============================================================================
-- Function: create_transport_lines_mview
-- Description:
--   Creates a materialized view that merges transport lines from:
--     - `lines_table` (ways: e.g. highway, railway),
--     - `multilines_table` (relations: e.g. route relations).
--
--   Each row gets a hash-based `id` and is marked with a `source_type`
--   ('way' or 'relation'). Multilingual name columns are added.
--
-- Parameters:
--   lines_table       TEXT - Table with way-based transport lines.
--   multilines_table  TEXT - Table with relation-based transport lines.
--   view_name         TEXT - Final materialized view name.
--
-- Notes:
--   - Input tables must include geometry, osm_id, type, class, name, and transport tags.
--   - Only valid geometries (LineString) are included from relation sources.
--   - View uses GiST index on geometry and unique index on `id`.
-- ============================================================================

DROP FUNCTION IF EXISTS create_transport_lines_mview;

CREATE OR REPLACE FUNCTION create_transport_lines_mview(
  lines_table TEXT,
  multilines_table TEXT,
  view_name TEXT
)
RETURNS void AS $$
DECLARE
  lang_columns TEXT := get_language_columns();
  tmp_view_name TEXT := view_name || '_tmp';
  unique_columns TEXT := 'id';
  sql_create TEXT;
BEGIN
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
        isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
        isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
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
        isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
        isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
        tags,
        member,
        'relation' AS source_type,
        %s
      FROM %I
      WHERE ST_GeometryType(geometry) = 'ST_LineString' AND geometry IS NOT NULL
    )
    SELECT DISTINCT ON (id) *
    FROM combined;
  $sql$, tmp_view_name, lang_columns, lines_table, lang_columns, multilines_table);

  PERFORM finalize_materialized_view(
    tmp_view_name,
    view_name,
    unique_columns,
    sql_create
  );
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
