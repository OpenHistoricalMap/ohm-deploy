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
    -- Produces all transport line features from ways, always including the
    -- standalone way feature plus any street-relation-expanded features.
    --
    -- Part 1 (standalone ways):
    --   Every way from osm_transport_lines appears as-is with its own
    --   properties. This represents the physical infrastructure's full
    --   lifespan, including periods not covered by any street relation.
    --
    -- Part 2 (street-relation-expanded):
    --   For each (way, street-relation) pair, an additional feature is
    --   produced with the relation's values overriding the way's:
    --     - name      : relation's name if present, else way's name.
    --     - start_date: from the relation.
    --     - end_date  : from the relation.
    --     - tags      : relation tags merged on top of way tags.
    --
    -- Example:
    --   Way 100 (start_date=1915) belongs to street relation -5000
    --   (start_date=1984, name="Oak Street").
    --
    --   Result:
    --   ┌──────────────┬────────┬──────────────┬────────────┬──────────┬──────────────────┐
    --   │ id           │ osm_id │ name         │ start_date │ end_date │ street_rel_osm_id│
    --   ├──────────────┼────────┼──────────────┼────────────┼──────────┼──────────────────┤
    --   │ 1_100        │ 100    │ (way's name) │ 1915       │          │ NULL             │  ← standalone way
    --   │ -5000_100    │ 100    │ Oak Street   │ 1984       │          │ -5000            │  ← relation overrides
    --   └──────────────┴────────┴──────────────┴────────────┴──────────┴──────────────────┘
    -- -----------------------------------------------------------------------
    way_street_expanded AS (
      -- Part 1: Standalone ways (always present)
      SELECT
        COALESCE(CAST(tl.id AS TEXT), '') || '_' || COALESCE(CAST(tl.osm_id AS TEXT), '') AS id,
        tl.osm_id,
        tl.geometry,
        tl.highway,
        tl.type,
        tl.class,
        tl.name,
        tl.tunnel,
        tl.bridge,
        tl.oneway,
        tl.ref,
        tl.z_order,
        tl.access,
        tl.service,
        tl.ford,
        tl.electrified,
        tl.highspeed,
        tl.usage,
        tl.railway,
        tl.aeroway,
        tl.route,
        tl.tags,
        tl.start_date,
        tl.end_date,
        NULL::bigint AS street_rel_osm_id
      FROM osm_transport_lines AS tl
      WHERE tl.geometry IS NOT NULL

      UNION ALL

      -- Part 2: Street-relation-expanded features
      SELECT
        COALESCE(CAST(sm.osm_id AS TEXT), '') || '_' || COALESCE(CAST(tl.osm_id AS TEXT), '') AS id,
        tl.osm_id,
        tl.geometry,
        COALESCE(NULLIF(sm.highway, ''), tl.highway)       AS highway,
        tl.type,
        tl.class,
        COALESCE(NULLIF(sm.name, ''), NULLIF(tl.name, '')) AS name,
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
        sm.tags || tl.tags AS tags,
        sm.start_date,
        sm.end_date,
        sm.osm_id AS street_rel_osm_id
      FROM osm_transport_lines AS tl
      INNER JOIN osm_street_multilines AS sm
        ON sm.member::bigint = tl.osm_id
        AND ST_GeometryType(sm.geometry) = 'ST_LineString'
      WHERE tl.geometry IS NOT NULL
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
