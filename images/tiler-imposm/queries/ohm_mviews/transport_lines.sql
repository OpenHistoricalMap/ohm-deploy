-- ============================================================================
-- Function: create_transport_lines_mview
-- Description:
--   Creates a materialized view that merges transport lines from:
--     - `osm_transport_lines` (ways: e.g. highway, railway),
--     - `osm_transport_multilines` (relations: e.g. route relations).
--
--   Each row gets a concatenated `id` (id + osm_id) and is marked with a 
--   `source_type` ('way' or 'relation'). Multilingual name columns are added.
--   Supports geometry simplification and filtering by type/class.
--
-- Parameters:
--   view_name            TEXT    - Final materialized view name.
--   simplified_tolerance INTEGER - Tolerance for ST_Simplify (0 = no simplification).
--   types                TEXT[]  - Array of types to include (use ARRAY['*'] for all).
--   classes              TEXT[]  - Array of classes to include (use ARRAY['*'] for all).
--
-- Notes:
--   - Filtering uses OR logic: (type IN types) OR (class IN classes).
--   - Only valid geometries (LineString) are included from relation sources.
--   - View uses GiST index on geometry and unique index on `id`.
-- ============================================================================

DROP FUNCTION IF EXISTS create_transport_lines_mview;

CREATE OR REPLACE FUNCTION create_transport_lines_mview(
  view_name TEXT,
  simplified_tolerance INTEGER,
  types TEXT[],
  classes TEXT[]
)
RETURNS void AS $$
DECLARE
  lang_columns TEXT := get_language_columns();
  tmp_view_name TEXT := view_name || '_tmp';
  unique_columns TEXT := 'id';
  type_filter TEXT;
  class_filter TEXT;
  sql_create TEXT;
BEGIN
  -- Build type filter: '*' means all types
  IF types @> ARRAY['*'] THEN
    type_filter := '1=1';
  ELSE
    type_filter := format('type = ANY(%L)', types);
  END IF;

  -- Build class filter: '*' means all classes
  IF classes @> ARRAY['*'] THEN
    class_filter := '1=1';
  ELSE
    class_filter := format('class = ANY(%L)', classes);
  END IF;

  sql_create := format($sql$
    CREATE MATERIALIZED VIEW %I AS
    WITH combined AS (
      SELECT
        (COALESCE(CAST(id AS TEXT), '') || '_' || COALESCE(CAST(osm_id AS TEXT), '')) AS id,
        ABS(osm_id) AS osm_id,
        CASE 
          WHEN %s > 0 THEN ST_Simplify(geometry, %s)
          ELSE geometry
        END AS geometry,
        --  Detect highways in construcion https://github.com/OpenHistoricalMap/issues/issues/1151
        CASE
            WHEN highway = 'construction' THEN
                -- If the 'construction' tag has a value, append '_construction'. Otherwise, use 'road_construction'.
                COALESCE(NULLIF(tags->'construction', '') || '_construction', 'road_construction')
            ELSE type
        END AS type,
        NULLIF(tags->'construction', '') AS construction,
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
        NULLIF(railway, '') AS railway,
        NULLIF(aeroway, '') AS aeroway,
        NULLIF(highway, '') AS highway,
        NULLIF(route, '') AS route,
        NULLIF(start_date, '') AS start_date,
        NULLIF(end_date, '') AS end_date,
        isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
        isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
        tags,
        NULL AS member,
        'way' AS source_type,
        %s
      FROM osm_transport_lines
      WHERE geometry IS NOT NULL
        AND ( %s
        OR %s)

      UNION ALL

      SELECT
        (COALESCE(CAST(id AS TEXT), '') || '_' || COALESCE(CAST(osm_id AS TEXT), '')) AS id,
        ABS(osm_id) AS osm_id,
        CASE 
          WHEN %s > 0 THEN ST_Simplify(geometry, %s)
          ELSE geometry
        END AS geometry,
        CASE
            WHEN highway = 'construction' THEN
                -- If the 'construction' tag has a value, append '_construction'. Otherwise, use 'road_construction'.
                COALESCE(NULLIF(tags->'construction', '') || '_construction', 'road_construction')
            ELSE type
        END AS type,
        NULLIF(tags->'construction', '') AS construction,
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
        NULLIF(railway, '') AS railway,
        NULLIF(aeroway, '') AS aeroway,
        NULLIF(highway, '') AS highway,
        NULLIF(route, '') AS route,
        NULLIF(start_date, '') AS start_date,
        NULLIF(end_date, '') AS end_date,
        isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
        isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
        tags,
        member,
        'relation' AS source_type,
        %s
      FROM osm_transport_multilines
      WHERE ST_GeometryType(geometry) = 'ST_LineString' AND geometry IS NOT NULL
        AND (%s
        OR %s)
    )
    SELECT DISTINCT ON (id) *
    FROM combined;
  $sql$, tmp_view_name, 
         simplified_tolerance, simplified_tolerance, lang_columns, type_filter, class_filter,
         simplified_tolerance, simplified_tolerance, lang_columns, type_filter, class_filter);

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
SELECT create_transport_lines_mview('mv_transport_lines_z5', 1000, ARRAY['motorway', 'motorway_link', 'trunk', 'trunk_link', 'construction', 'primary', 'primary_link', 'rail', 'secondary', 'secondary_link'], ARRAY['railway']);
SELECT create_transport_lines_mview('mv_transport_lines_z6_7', 200, ARRAY['motorway', 'motorway_link', 'trunk', 'trunk_link', 'construction', 'primary', 'primary_link', 'rail', 'secondary', 'secondary_link'], ARRAY['railway']);
SELECT create_transport_lines_mview('mv_transport_lines_z8_9', 100, ARRAY['motorway', 'motorway_link', 'trunk', 'trunk_link', 'construction', 'primary', 'primary_link', 'rail', 'secondary', 'secondary_link', 'tertiary', 'tertiary_link', 'taxiway', 'runway'], ARRAY['railway']);
SELECT create_transport_lines_mview('mv_transport_lines_z10_12', 20, ARRAY['motorway', 'motorway_link', 'trunk', 'trunk_link', 'construction', 'primary', 'primary_link', 'rail', 'secondary', 'secondary_link', 'tertiary', 'tertiary_link', 'taxiway', 'runway'], ARRAY['railway']);
SELECT create_transport_lines_mview('mv_transport_lines_z13_15', 5, ARRAY['motorway', 'motorway_link', 'trunk', 'trunk_link', 'construction', 'primary', 'primary_link', 'rail', 'secondary', 'secondary_link', 'tertiary', 'tertiary_link', 'miniature', 'narrow_gauge', 'dismantled', 'abandoned', 'disused', 'razed', 'light_rail', 'preserved', 'proposed', 'tram', 'funicular', 'monorail', 'taxiway', 'runway', 'raceway', 'residential', 'service', 'unclassified'], ARRAY['railway']);
SELECT create_transport_lines_mview('mv_transport_lines_z16_20', 0, ARRAY['*'], ARRAY['railway','route']);
