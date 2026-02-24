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
    -- CTE: attr_diff_pairs
    --
    -- Identifies (way, street-relation) pairs where the relation overrides
    -- at least one attribute compared to the way. Only these pairs produce
    -- separate relation-expanded features and trigger date trimming on the
    -- standalone way. When all attributes match, the way keeps its original
    -- date range and no expanded feature is emitted.
    -- -----------------------------------------------------------------------
    attr_diff_pairs AS (
      SELECT sm.member::bigint AS way_osm_id, sm.osm_id AS rel_osm_id, sm.start_date AS rel_start_date
      FROM osm_transport_lines AS tl
      INNER JOIN osm_street_multilines AS sm
        ON sm.member::bigint = tl.osm_id
        AND ST_GeometryType(sm.geometry) = 'ST_LineString'
      WHERE tl.geometry IS NOT NULL
        AND (
          (NULLIF(sm.name, '')         IS NOT NULL AND sm.name         IS DISTINCT FROM tl.name)
          OR (NULLIF(sm.highway, '')   IS NOT NULL AND sm.highway      IS DISTINCT FROM tl.highway)
          OR (NULLIF(sm.ref, '')       IS NOT NULL AND sm.ref          IS DISTINCT FROM tl.ref)
          OR (NULLIF(sm.access, '')    IS NOT NULL AND sm.access       IS DISTINCT FROM tl.access)
          OR (NULLIF(sm.service, '')   IS NOT NULL AND sm.service      IS DISTINCT FROM tl.service)
          OR (NULLIF(sm.ford, '')      IS NOT NULL AND sm.ford         IS DISTINCT FROM tl.ford)
          OR (NULLIF(sm.electrified,'')IS NOT NULL AND sm.electrified  IS DISTINCT FROM tl.electrified)
          OR (NULLIF(sm.highspeed, '') IS NOT NULL AND sm.highspeed    IS DISTINCT FROM tl.highspeed)
          OR (NULLIF(sm.usage, '')     IS NOT NULL AND sm.usage        IS DISTINCT FROM tl.usage)
          OR (NULLIF(sm.railway, '')   IS NOT NULL AND sm.railway      IS DISTINCT FROM tl.railway)
          OR (NULLIF(sm.aeroway, '')   IS NOT NULL AND sm.aeroway      IS DISTINCT FROM tl.aeroway)
          OR (NULLIF(sm.route, '')     IS NOT NULL AND sm.route        IS DISTINCT FROM tl.route)
          OR (sm.tunnel  IS NOT NULL AND sm.tunnel  IS DISTINCT FROM tl.tunnel)
          OR (sm.bridge  IS NOT NULL AND sm.bridge  IS DISTINCT FROM tl.bridge)
          OR (sm.oneway  IS NOT NULL AND sm.oneway  IS DISTINCT FROM tl.oneway)
        )
    ),
    -- -----------------------------------------------------------------------
    -- CTE: street_rel_dates
    --
    -- For each way with attribute-changing street relations, computes the
    -- earliest relation start_date. Used to trim the standalone way's
    -- end_date so it doesn't overlap with the relation's time period.
    -- Relations with identical attributes are excluded (the way keeps its
    -- original date range for those).
    -- -----------------------------------------------------------------------
    street_rel_dates AS (
      SELECT
        way_osm_id,
        MIN(NULLIF(rel_start_date, '')) AS earliest_rel_start
      FROM attr_diff_pairs
      WHERE NULLIF(rel_start_date, '') IS NOT NULL
      GROUP BY way_osm_id
    ),
    -- -----------------------------------------------------------------------
    -- CTE: way_street_expanded
    --
    -- Produces all transport line features from ways, always including the
    -- standalone way feature plus any street-relation-expanded features.
    --
    -- Part 1 (standalone ways):
    --   Every way from osm_transport_lines appears as-is with its own
    --   properties. When the way belongs to a street relation that changes
    --   attributes, the way's end_date is trimmed to the earliest such
    --   relation's start_date so the time periods do not overlap. When the
    --   relation has identical attributes, the way keeps its original dates
    --   (no split needed).
    --
    -- Part 2 (street-relation-expanded):
    --   Only produced when the relation changes at least one attribute.
    --   The relation's values override the way's:
    --     - name      : relation's name if present, else way's name.
    --     - start_date: from the relation.
    --     - end_date  : from the relation.
    --     - tags      : relation tags merged on top of way tags.
    --
    -- Example A (relation changes name → split):
    --   Way 100 (start_date=1915, name="Old Road") belongs to street
    --   relation -5000 (start_date=1984, name="Oak Street").
    --
    --   Result (no overlapping time periods):
    --   ┌──────────────┬────────┬──────────────┬────────────┬──────────┬──────────────────┐
    --   │ id           │ osm_id │ name         │ start_date │ end_date │ street_rel_osm_id│
    --   ├──────────────┼────────┼──────────────┼────────────┼──────────┼──────────────────┤
    --   │ 1_100        │ 100    │ Old Road     │ 1915       │ 1984     │ NULL             │  ← way trimmed
    --   │ -5000_100    │ 100    │ Oak Street   │ 1984       │          │ -5000            │  ← relation overrides
    --   └──────────────┴────────┴──────────────┴────────────┴──────────┴──────────────────┘
    --
    -- Example B (relation has same attributes → merged):
    --   Way 100 (start_date=1915, name="Oak Street") belongs to street
    --   relation -5000 (start_date=1984, name="Oak Street"). All attributes
    --   are identical, so no expanded feature is produced.
    --
    --   Result (single feature with full date range):
    --   ┌──────────────┬────────┬──────────────┬────────────┬──────────┬──────────────────┐
    --   │ id           │ osm_id │ name         │ start_date │ end_date │ street_rel_osm_id│
    --   ├──────────────┼────────┼──────────────┼────────────┼──────────┼──────────────────┤
    --   │ 1_100        │ 100    │ Oak Street   │ 1915       │          │ NULL             │  ← way untrimmed
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
        LEAST(NULLIF(tl.end_date, ''), srd.earliest_rel_start) AS end_date,
        NULL::bigint AS street_rel_osm_id
      FROM osm_transport_lines AS tl
      LEFT JOIN street_rel_dates AS srd ON srd.way_osm_id = tl.osm_id
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
        AND EXISTS (
          SELECT 1 FROM attr_diff_pairs AS adp
          WHERE adp.way_osm_id = tl.osm_id AND adp.rel_osm_id = sm.osm_id
        )
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
