-- ============================================================================
-- Materialized view: mv_transport_lines_z16_20
-- Description:
--   Base materialized view that merges transport lines from:
--     - osm_transport_lines (ways: e.g. highway, railway),
--     - osm_transport_multilines (relations: e.g. route relations),
--     - osm_street_multilines (type=street relations, via street_multilines.json).
--
--   Ways that are members of type=street relations are expanded: each
--   (way, street-relation) pair produces one feature. The relation's values
--   override the way's values:
--     - name      : relation's name if present, else way's name (fallback).
--     - start_date: always from the relation when one exists, else from way.
--     - end_date  : always from the relation when one exists, else from way.
--     - other tags: relation's tags applied on top (way tags as base).
--   Ways with no type=street membership produce a single unchanged feature.
--
--   Each row gets a concatenated id (id + osm_id) and is marked with a
--   source_type ('way' or 'relation'). Multilingual name columns are added.
--
--   All derived zoom-level views (z13_15, z10_12, etc.) cascade from this one.
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS mv_transport_lines_z16_20 CASCADE;

DO $do$
DECLARE
  lang_columns TEXT := get_language_columns();
  sql_create TEXT;
BEGIN
  sql_create := format($sql$
    CREATE MATERIALIZED VIEW mv_transport_lines_z16_20_tmp AS
    WITH
    -- -----------------------------------------------------------------------
    -- CTE: way_street_expanded
    --
    -- Expands ways by their type=street relation memberships.
    --
    -- osm_street_multilines has one row per (type=street relation, way member).
    -- LEFT JOIN expands each way into N rows when it belongs to N street
    -- relations, or leaves it as a single row when it has no membership.
    --
    -- Override rules (relation values take priority when a match exists):
    --   name      : relation's name if present, else way's name (fallback).
    --   start_date: relation's when exists, else way's.
    --   end_date  : relation's when exists, else way's.
    --   tags      : relation tags merged on top of way tags (way wins conflicts).
    --
    -- Example: Given these source tables:
    --
    --   osm_transport_lines (ways):
    --   ┌────┬────────┬──────────┬──────────────┬────────────┬──────────┐
    --   │ id │ osm_id │ highway  │ name         │ start_date │ end_date │
    --   ├────┼────────┼──────────┼──────────────┼────────────┼──────────┤
    --   │ 1  │ 100    │ primary  │ Main Street  │ 1920       │          │
    --   │ 2  │ 200    │ tertiary │ Oak Ave      │ 1950       │          │
    --   │ 3  │ 300    │ rail     │ Rail Line 5  │ 1880       │ 1960     │
    --   └────┴────────┴──────────┴──────────────┴────────────┴──────────┘
    --
    --   osm_street_multilines (type=street relations):
    --   ┌─────────┬────────┬──────────────────┬────────────┬──────────┐
    --   │ osm_id  │ member │ name             │ start_date │ end_date │
    --   ├─────────┼────────┼──────────────────┼────────────┼──────────┤
    --   │ -5000   │ 100    │ Av. Principal    │ 1800       │          │  ← way 100 in relation -5000
    --   │ -5001   │ 100    │ Calle Mayor      │ 1750       │ 1800     │  ← way 100 also in relation -5001
    --   └─────────┴────────┴──────────────────┴────────────┴──────────┘
    --
    --   Result of way_street_expanded:
    --   ┌──────────────┬────────┬──────────┬──────────────────┬────────────┬──────────┐
    --   │ id           │ osm_id │ highway  │ name             │ start_date │ end_date │
    --   ├──────────────┼────────┼──────────┼──────────────────┼────────────┼──────────┤
    --   │ -5000_100    │ 100    │ primary  │ Av. Principal    │ 1800       │          │  ← relation -5000 overrides
    --   │ -5001_100    │ 100    │ primary  │ Calle Mayor      │ 1750       │ 1800     │  ← relation -5001 overrides
    --   │ 2_200        │ 200    │ tertiary │ Oak Ave          │ 1950       │          │  ← no relation, keeps way values
    --   │ 3_300        │ 300    │ rail     │ Rail Line 5      │ 1880       │ 1960     │  ← no relation, keeps way values
    --   └──────────────┴────────┴──────────┴──────────────────┴────────────┴──────────┘
    --
    --   Note: way 100 (Main Street) appears TWICE because it belongs to 2
    --   street relations. Each row gets the relation's name and dates.
    --   Ways 200 and 300 have no street relation, so they appear once with
    --   their original values. The id uses tl.id_tl.osm_id (positive_positive).
    -- -----------------------------------------------------------------------
    way_street_expanded AS (
      SELECT
        CASE
          WHEN street_mline_table.osm_id IS NOT NULL THEN
            COALESCE(CAST(street_mline_table.osm_id AS TEXT), '') || '_' || COALESCE(CAST(tranport_line_table.osm_id AS TEXT), '')
          ELSE
            COALESCE(CAST(tranport_line_table.id AS TEXT), '') || '_' || COALESCE(CAST(tranport_line_table.osm_id AS TEXT), '')
        END AS id,
        tranport_line_table.osm_id,
        tranport_line_table.geometry,
        COALESCE(NULLIF(street_mline_table.highway, ''), tranport_line_table.highway) AS highway,
        tranport_line_table.type,
        tranport_line_table.class,
        CASE
          WHEN street_mline_table.osm_id IS NOT NULL
            THEN COALESCE(NULLIF(street_mline_table.name, ''), NULLIF(tranport_line_table.name, ''))
          ELSE tranport_line_table.name
        END AS name,
        COALESCE(street_mline_table.tunnel,                tranport_line_table.tunnel)                AS tunnel,
        COALESCE(street_mline_table.bridge,                tranport_line_table.bridge)                AS bridge,
        COALESCE(street_mline_table.oneway,                tranport_line_table.oneway)                AS oneway,
        COALESCE(NULLIF(street_mline_table.ref,  ''),      tranport_line_table.ref)                   AS ref,
        COALESCE(street_mline_table.z_order,               tranport_line_table.z_order)               AS z_order,
        COALESCE(NULLIF(street_mline_table.access,  ''),   tranport_line_table.access)                AS access,
        COALESCE(NULLIF(street_mline_table.service, ''),   tranport_line_table.service)               AS service,
        COALESCE(NULLIF(street_mline_table.ford,    ''),   tranport_line_table.ford)                  AS ford,
        COALESCE(NULLIF(street_mline_table.electrified,''),tranport_line_table.electrified)           AS electrified,
        COALESCE(NULLIF(street_mline_table.highspeed,''),  tranport_line_table.highspeed)             AS highspeed,
        COALESCE(NULLIF(street_mline_table.usage,   ''),   tranport_line_table.usage)                 AS usage,
        COALESCE(NULLIF(street_mline_table.railway, ''),   tranport_line_table.railway)               AS railway,
        COALESCE(NULLIF(street_mline_table.aeroway, ''),   tranport_line_table.aeroway)               AS aeroway,
        COALESCE(NULLIF(street_mline_table.route,   ''),   tranport_line_table.route)                 AS route,
        CASE
          WHEN street_mline_table.osm_id IS NOT NULL THEN street_mline_table.tags || tranport_line_table.tags
          ELSE tranport_line_table.tags
        END AS tags,
        CASE WHEN street_mline_table.osm_id IS NOT NULL THEN street_mline_table.start_date ELSE tranport_line_table.start_date END AS start_date,
        CASE WHEN street_mline_table.osm_id IS NOT NULL THEN street_mline_table.end_date   ELSE tranport_line_table.end_date   END AS end_date,
        street_mline_table.osm_id AS street_rel_osm_id
      FROM osm_transport_lines AS tranport_line_table
      LEFT JOIN osm_street_multilines AS street_mline_table
        ON street_mline_table.member::bigint = tranport_line_table.osm_id
        AND ST_GeometryType(street_mline_table.geometry) = 'ST_LineString'
      WHERE tranport_line_table.geometry IS NOT NULL
    ),
    combined AS (
      -- -------------------------------------------------------------------
      -- Ways (possibly expanded by street relations)
      -- -------------------------------------------------------------------
      SELECT
        id,
        ABS(osm_id) AS osm_id,
        geometry,
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
        ABS(street_rel_osm_id) AS relation,
        'way' AS source_type,
        %s
      FROM way_street_expanded
      WHERE NOT EXISTS (
        SELECT 1 FROM osm_transport_multilines AS tm
        WHERE tm.member::bigint = way_street_expanded.osm_id
      )

      UNION ALL

      -- -------------------------------------------------------------------
      -- Transport relation members (route relations, etc.)
      -- -------------------------------------------------------------------
      SELECT
        (COALESCE(CAST(id AS TEXT), '') || '_' || COALESCE(CAST(osm_id AS TEXT), '')) AS id,
        ABS(member::bigint) AS osm_id,
        geometry,
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
        ABS(osm_id) AS relation,
        'relation' AS source_type,
        %s
      FROM osm_transport_multilines
      WHERE ST_GeometryType(geometry) = 'ST_LineString' AND geometry IS NOT NULL
    )
    SELECT DISTINCT ON (id) *
    FROM combined;
  $sql$, lang_columns, lang_columns);

  PERFORM finalize_materialized_view(
    'mv_transport_lines_z16_20_tmp',
    'mv_transport_lines_z16_20',
    'id',
    sql_create
  );
END;
$do$;


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
