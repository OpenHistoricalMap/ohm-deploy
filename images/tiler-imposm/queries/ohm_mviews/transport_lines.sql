-- ============================================================================
-- Function: create_transport_lines_mview
-- Description:
--   Creates a materialized view that merges transport lines from:
--     - `osm_transport_lines` (ways: e.g. highway, railway),
--     - `osm_transport_multilines` (relations: e.g. route relations),
--     - `osm_street_multilines` (type=street relations, via street_multilines.json).
--
--   Ways that are members of `type=street` relations are expanded: each
--   (way, street-relation) pair produces one feature. The relation's values
--   override the way's values:
--     - name      : relation's name if present, else way's name (fallback).
--     - start_date: always from the relation when one exists, else from way.
--     - end_date  : always from the relation when one exists, else from way.
--     - other tags: relation's tags applied on top (way tags as base).
--   Ways with no type=street membership produce a single unchanged feature.
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
--   - Requires osm_street_multilines (imposm re-import with street_multilines.json).
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
  tl_type_filter TEXT;
  tl_class_filter TEXT;
  sql_create TEXT;
BEGIN
  -- Build type/class filters.
  -- tl_* variants are qualified with the tl. alias for the way_street_expanded
  -- CTE where the LEFT JOIN with osm_street_multilines makes bare references ambiguous.
  -- Unqualified variants are used for osm_transport_multilines (no join, no alias).
  IF types @> ARRAY['*'] THEN
    type_filter := '1=1';
    tl_type_filter := '1=1';
  ELSE
    type_filter := format('type = ANY(%L)', types);
    tl_type_filter := format('tl.type = ANY(%L)', types);
  END IF;

  IF classes @> ARRAY['*'] THEN
    class_filter := '1=1';
    tl_class_filter := '1=1';
  ELSE
    class_filter := format('class = ANY(%L)', classes);
    tl_class_filter := format('tl.class = ANY(%L)', classes);
  END IF;

  sql_create := format($sql$
    CREATE MATERIALIZED VIEW %I AS
    WITH
    -- -----------------------------------------------------------------------
    -- Step 1: Expand ways by type=street relations.
    --
    -- osm_street_multilines has one row per (type=street relation, way member).
    -- LEFT JOIN expands each way into N rows when it belongs to N street
    -- relations, or leaves it as a single row when it has no membership.
    --
    -- Override rules (relation values take priority when a match exists):
    --   name      : way's name if present, else relation's name (fallback).
    --   start_date: relation's when exists, else way's.
    --   end_date  : relation's when exists, else way's.
    --   tags      : relation tags merged on top of way tags (way wins conflicts).
    --
    -- ID scheme:
    --   - Street-relation row : sm.osm_id  || '_' || tl.osm_id
    --                           (sm.osm_id is negative for relations in imposm)
    --   - Plain-way row       : tl.id      || '_' || tl.osm_id
    --                           (both positive; format never collides with above)
    -- -----------------------------------------------------------------------
    way_street_expanded AS (
      SELECT
        CASE
          WHEN sm.osm_id IS NOT NULL THEN
            COALESCE(CAST(sm.osm_id AS TEXT), '') || '_' || COALESCE(CAST(tl.osm_id AS TEXT), '')
          ELSE
            COALESCE(CAST(tl.id AS TEXT), '') || '_' || COALESCE(CAST(tl.osm_id AS TEXT), '')
        END AS id,
        tl.osm_id,
        tl.geometry,
        -- highway: relation's value when present, else way's
        COALESCE(NULLIF(sm.highway, ''), tl.highway) AS highway,
        tl.type,
        tl.class,
        -- name: relation's name if present, else way's name (fallback)
        CASE
          WHEN sm.osm_id IS NOT NULL
            THEN COALESCE(NULLIF(sm.name, ''), NULLIF(tl.name, ''))
          ELSE tl.name
        END AS name,
        -- tunnel/bridge/oneway/ref/z_order/access/service/ford:
        --   relation's value when present, else way's
        COALESCE(sm.tunnel,                tl.tunnel)                AS tunnel,
        COALESCE(sm.bridge,                tl.bridge)                AS bridge,
        COALESCE(sm.oneway,                tl.oneway)                AS oneway,
        COALESCE(NULLIF(sm.ref,  ''),      tl.ref)                   AS ref,
        COALESCE(sm.z_order,               tl.z_order)               AS z_order,
        COALESCE(NULLIF(sm.access,  ''),   tl.access)                AS access,
        COALESCE(NULLIF(sm.service, ''),   tl.service)               AS service,
        COALESCE(NULLIF(sm.ford,    ''),   tl.ford)                  AS ford,
        COALESCE(NULLIF(sm.electrified,''),tl.electrified)           AS electrified,
        COALESCE(NULLIF(sm.highspeed,''),  tl.highspeed)             AS highspeed,
        COALESCE(NULLIF(sm.usage,   ''),   tl.usage)                 AS usage,
        COALESCE(NULLIF(sm.railway, ''),   tl.railway)               AS railway,
        COALESCE(NULLIF(sm.aeroway, ''),   tl.aeroway)               AS aeroway,
        COALESCE(NULLIF(sm.route,   ''),   tl.route)                 AS route,
        -- tags: relation tags on top, way tags as base (way wins on conflict)
        CASE
          WHEN sm.osm_id IS NOT NULL THEN sm.tags || tl.tags
          ELSE tl.tags
        END AS tags,
        -- dates: relation's values when in a street relation, else way's
        CASE WHEN sm.osm_id IS NOT NULL THEN sm.start_date ELSE tl.start_date END AS start_date,
        CASE WHEN sm.osm_id IS NOT NULL THEN sm.end_date   ELSE tl.end_date   END AS end_date
      FROM osm_transport_lines tl
      LEFT JOIN osm_street_multilines sm
        ON sm.member::bigint = tl.osm_id
        AND ST_GeometryType(sm.geometry) = 'ST_LineString'
      WHERE tl.geometry IS NOT NULL
        AND ( %s OR %s )
    ),
    combined AS (
      -- -------------------------------------------------------------------
      -- Ways (possibly expanded by street relations)
      -- -------------------------------------------------------------------
      SELECT
        id,
        ABS(osm_id) AS osm_id,
        CASE
          WHEN %s > 0 THEN ST_Simplify(geometry, %s)
          ELSE geometry
        END AS geometry,
        --  Detect highways in construction https://github.com/OpenHistoricalMap/issues/issues/1151
        CASE
            WHEN highway = 'construction' THEN
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
      FROM way_street_expanded

      UNION ALL

      -- -------------------------------------------------------------------
      -- Transport relation members (route relations, etc.)
      -- -------------------------------------------------------------------
      SELECT
        (COALESCE(CAST(id AS TEXT), '') || '_' || COALESCE(CAST(osm_id AS TEXT), '')) AS id,
        ABS(osm_id) AS osm_id,
        CASE
          WHEN %s > 0 THEN ST_Simplify(geometry, %s)
          ELSE geometry
        END AS geometry,
        CASE
            WHEN highway = 'construction' THEN
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
         tl_type_filter, tl_class_filter,
         simplified_tolerance, simplified_tolerance, lang_columns,
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
DROP MATERIALIZED VIEW IF EXISTS mv_transport_lines_z16_20 CASCADE;
SELECT create_transport_lines_mview('mv_transport_lines_z16_20', 0, ARRAY['*'], ARRAY['railway','route']);
SELECT create_mview_line_from_mview('mv_transport_lines_z16_20', 'mv_transport_lines_z13_15', 5, 'type IN (''motorway'', ''motorway_link'', ''trunk'', ''trunk_link'', ''construction'', ''primary'', ''primary_link'', ''rail'', ''secondary'', ''secondary_link'', ''tertiary'', ''tertiary_link'', ''miniature'', ''narrow_gauge'', ''dismantled'', ''abandoned'', ''disused'', ''razed'', ''light_rail'', ''preserved'', ''proposed'', ''tram'', ''funicular'', ''monorail'', ''taxiway'', ''runway'', ''raceway'', ''residential'', ''service'', ''unclassified'') OR class IN (''railway'')');
SELECT create_mview_line_from_mview('mv_transport_lines_z13_15', 'mv_transport_lines_z10_12', 20, 'type IN (''motorway'', ''motorway_link'', ''trunk'', ''trunk_link'', ''construction'', ''primary'', ''primary_link'', ''rail'', ''secondary'', ''secondary_link'', ''tertiary'', ''tertiary_link'', ''miniature'', ''narrow_gauge'', ''dismantled'', ''abandoned'', ''disused'', ''razed'', ''light_rail'', ''preserved'', ''proposed'', ''tram'', ''funicular'', ''monorail'', ''taxiway'', ''runway'') OR class IN (''railway'')');
SELECT create_mview_line_from_mview('mv_transport_lines_z10_12', 'mv_transport_lines_z8_9', 100, NULL);
SELECT create_mview_line_from_mview('mv_transport_lines_z8_9', 'mv_transport_lines_z6_7', 200 , 'type IN (''motorway'', ''motorway_link'', ''trunk'', ''trunk_link'', ''construction'', ''primary'', ''primary_link'', ''rail'', ''secondary'', ''secondary_link'') OR class IN (''railway'')');
SELECT create_mview_line_from_mview('mv_transport_lines_z6_7', 'mv_transport_lines_z5', 1000 , NULL);



-- Refresh lines views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_lines_z5;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_lines_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_lines_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_lines_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_lines_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_lines_z16_20;
