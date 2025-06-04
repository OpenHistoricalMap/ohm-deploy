-- ============================================================================
-- Function: create_transport_lines_mview
-- Description:
--   createsa materialized view that merges transport lines and multi-lines
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
  sql_drop TEXT;
  sql_create TEXT;
  sql_unique_index TEXT;
  sql_geometry_index TEXT;
BEGIN
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


-- ============================================================================
-- Function: create_transport_points_centroids_mview
-- Description:
--   This function createsa materialized view that merges transport area centroids 
--   (calculated from polygons) and transport points into a unified layer.
--
-- Parameters:
--   view_name     TEXT              - The name of the materialized view to create.
--   min_area      DOUBLE PRECISION - The minimum area (in m²) to include transport areas.
--
-- Notes:
--   - Centroids use ST_MaximumInscribedCircle for polygonal geometries.
--   - Points are included directly with NULL area_m2 to reduce vector tile size.
--   - Only area features with non-empty "name" are included.
--   - Multilingual tags are dynamically included from the `languages` table.
--   - Geometry is indexed using GiST; uniqueness enforced on (osm_id, type, class).
-- ============================================================================

DROP FUNCTION IF EXISTS create_transport_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_transport_points_centroids_mview(
    view_name TEXT,
    min_area DOUBLE PRECISION DEFAULT 0
)
RETURNS void AS $$
DECLARE 
    sql_drop TEXT;
    sql_create TEXT;
    sql_index TEXT;
    sql_unique_index TEXT;
    lang_columns TEXT;
BEGIN
    RAISE NOTICE 'Creating  transport points and centroids view: %', view_name;

    lang_columns := get_language_columns();

    RAISE NOTICE 'Dropping materialized view %', view_name;
    sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
    EXECUTE sql_drop;

    RAISE NOTICE 'Creating materialized view % with area > %', view_name, min_area;
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            (ST_MaximumInscribedCircle(geometry)).center AS geometry,
            osm_id, 
            name, 
            class, 
            type, 
            start_date, 
            end_date, 
            ROUND(area)::bigint AS area_m2,
            tags,
            %s
        FROM osm_transport_areas
        WHERE name IS NOT NULL AND name <> '' AND area > %L

        UNION ALL

        SELECT 
            geometry,
            osm_id, 
            name, 
            class, 
            type, 
            start_date, 
            end_date, 
            NULL AS area_m2, 
            tags,
            %s
        FROM osm_transport_points;
    $sql$, view_name, lang_columns, min_area, lang_columns);
    EXECUTE sql_create;

    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;

    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type, class);', view_name, view_name);
    EXECUTE sql_unique_index;

    RAISE NOTICE 'Materialized view % created successfully.', view_name;
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

-- ============================================================================
-- Create materialized views for transport areas
-- ============================================================================
SELECT create_generic_mview('osm_transport_areas', 'mv_transport_areas_z12_20', ARRAY['osm_id', 'type']);

-- ============================================================================
-- Create materialized views for transport points centroids
-- ============================================================================
SELECT create_transport_points_centroids_mview('mv_transport_points_centroids_z14_20', 0);
