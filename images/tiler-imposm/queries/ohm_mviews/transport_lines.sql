-- ============================================================================
-- Function: create_transport_lines_mview
-- Description:
--   Creates a materialized view that merges transport lines from two source tables:
--     - `lines_table`: way-based transport lines (e.g., highway, railway).
--     - `multilines_table`: relation-based transport lines (e.g., route relations).
--
--   Each row is uniquely identified by a hash-based `id`, combining relevant attributes.
--   Records from relations include a `member` value and are marked as `source_type = 'relation'`,
--   while way-based features are marked as `source_type = 'way'`.
--
--   The resulting view supports temporal filtering and includes multilingual name columns.
--
-- Parameters:
--   lines_table       TEXT   - Table containing way-based transport lines.
--   multilines_table  TEXT   - Table containing relation-based transport lines.
--   view_name         TEXT   - Name of the final materialized view to be created.
--
-- Behavior:
--   - Drops and recreates a temporary view for safe replacement.
--   - Adds language-specific name columns using the `languages` table.
--   - Creates a GiST index on geometry and a unique index on (id).
--
-- Notes:
--   - Input tables must include fields: geometry, osm_id, type, class, name, and transport tags.
--   - Only valid geometries (LineString) are included from relation sources.
-- ============================================================================

DROP FUNCTION IF EXISTS create_transport_lines_mview;
CREATE OR REPLACE FUNCTION create_transport_lines_mview(
  lines_table TEXT,
  multilines_table TEXT,
  view_name TEXT
)
RETURNS void AS $$
DECLARE
  lang_columns TEXT;
  sql_create TEXT;
  tmp_view_name TEXT := view_name || '_tmp';
BEGIN
  lang_columns := get_language_columns();

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
  $sql$, tmp_view_name, lang_columns, lines_table, lang_columns, multilines_table);

  -- === LOG & EXECUTION SEQUENCE ===
  RAISE NOTICE '==> [START] Creating transport lines view: % (tmp: %)', view_name, tmp_view_name;

  RAISE NOTICE '==> [DROP TEMP] Dropping temporary view if exists: %', tmp_view_name;
  EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', tmp_view_name);

  RAISE NOTICE '==> [CREATE TEMP] Creating temporary materialized view: %', tmp_view_name;
  EXECUTE sql_create;

  RAISE NOTICE '==> [INDEX] Creating UNIQUE index on (id)';
  EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I(id);', tmp_view_name, tmp_view_name);

  RAISE NOTICE '==> [INDEX] Creating GiST index on geometry';
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST(geometry);', tmp_view_name, tmp_view_name);

  RAISE NOTICE '==> [DROP OLD] Dropping old view if exists: %', view_name;
  EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);

  RAISE NOTICE '==> [RENAME] Renaming % → %', tmp_view_name, view_name;
  EXECUTE format('ALTER MATERIALIZED VIEW %I RENAME TO %I;', tmp_view_name, view_name);

  RAISE NOTICE '==> [DONE] Materialized view % created and indexed.', view_name;
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
