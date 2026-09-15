-- ============================================================================
-- Materialized view: mv_transport_lines_z16_20
-- Description:
--   Base materialized view that merges transport lines from:
--     - osm_transport_lines (ways: e.g. highway, railway; via transport_lines.json),
--     - osm_transport_multilines (relations: e.g. route relations; via transport_multilines.json),
--     - osm_street_multilines (type=street relations; via street_multilines.json).
--
-- osm_transport_lines       = the WAYS. The physical geometry of the road/line.
--                             1 row per way. highway=*, railway=*.
--                             ALWAYS present when there is a road. <- the base

-- osm_transport_multilines  = ROUTE relations. They group ways.
--                             1 row per (relation, member way).
--                             e.g. numbered route, rail line.

-- osm_street_multilines     = STREET relations (type=street). They group ways
--                             under a street name. 1 row per (relation, member).
--                             e.g. "Main Street".

--   A way that belongs to a street or route relation is handled by clipping:
--   the relation renames/reclassifies the way only WITHIN the way's own date
--   range (never outside it), and the way fills any period no relation covers
--   (keeping its own name). A way with no relation renders as-is.
--     - name      : relation's name during its period, else the way's name.
--     - start_date/end_date: the overlap of the relation and the way.
--     - other tags: relation's tags on top of the way's (way tags as base).
--
--   Each row gets a concatenated id (id + osm_id) and a source_type
--   ('way' or 'relation'). Multilingual name columns are added.
--
--   All derived zoom-level views (z13_15, z10_12, etc.) cascade from this one.
-- ============================================================================

SET statement_timeout = 0;

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
    -- Find (way, street-relation) pairs where the relation changes something
    -- on the way (a name, a highway type, etc).
    --
    -- Example: an unnamed way belongs to a street relation named "Main Road".
    --          The name changes -> keep this pair (the way is a street member).
    -- If the relation changes nothing, the way is left alone (a plain way).
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
          OR (NULLIF(sm.street_running, '') IS NOT NULL AND sm.street_running IS DISTINCT FROM tl.street_running)
          OR (NULLIF(sm.railway, '')   IS NOT NULL AND sm.railway      IS DISTINCT FROM tl.railway)
          OR (NULLIF(sm.aeroway, '')   IS NOT NULL AND sm.aeroway      IS DISTINCT FROM tl.aeroway)
          OR (NULLIF(sm.aerialway, '') IS NOT NULL AND sm.aerialway    IS DISTINCT FROM tl.aerialway)
          OR (NULLIF(sm.route, '')     IS NOT NULL AND sm.route        IS DISTINCT FROM tl.route)
          OR (sm.expressway IS NOT NULL AND sm.expressway IS DISTINCT FROM tl.expressway)
          OR (sm.tunnel  IS NOT NULL AND sm.tunnel  IS DISTINCT FROM tl.tunnel)
          OR (sm.bridge  IS NOT NULL AND sm.bridge  IS DISTINCT FROM tl.bridge)
          OR (sm.oneway  IS NOT NULL AND sm.oneway  IS DISTINCT FROM tl.oneway)
        )
    ),
    -- -----------------------------------------------------------------------
    -- plain_ways — ways with NO street/route relation membership. They render
    -- as-is, with their own dates. (Street members are handled by the STREET
    -- block below; transport-multiline members by the ROUTE block below.)
    -- -----------------------------------------------------------------------
    plain_ways AS (
      SELECT
        COALESCE(CAST(tl.id AS TEXT), '') || '_' || COALESCE(CAST(tl.osm_id AS TEXT), '') AS id,
        tl.osm_id, tl.geometry, tl.highway, tl.type, tl.class, tl.name,
        tl.tunnel, tl.bridge, tl.oneway, tl.ref, tl.z_order, tl.access, tl.service,
        tl.ford, tl.electrified, tl.highspeed, tl.usage, tl.street_running, tl.railway, tl.aeroway, tl.aerialway,
        tl.route, tl.expressway, tl.tags,
        tl.start_date,
        NULLIF(tl.end_date, '') AS end_date,
        NULL::bigint AS street_rel_osm_id
      FROM osm_transport_lines AS tl
      WHERE tl.geometry IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM osm_transport_multilines AS tm
          WHERE tm.member::bigint = tl.osm_id AND ST_GeometryType(tm.geometry) = 'ST_LineString'
        )
        AND NOT EXISTS (
          SELECT 1 FROM attr_diff_pairs AS adp WHERE adp.way_osm_id = tl.osm_id
        )
    ),
    -- =======================================================================
    -- ROUTE / TRANSPORT RELATIONS (osm_transport_multilines) — fix #1320
    --
    -- A relation can rename or reclassify a way for a time period. The relation
    -- only counts while the way itself exists. So we clip the relation to the
    -- way's dates, and the way fills the time the relation does not cover.
    --
    -- Example: way exists 1900-2000. Relation "Main St" says 1850-1950.
    --   -> "Main St" shows 1900-1950 (clipped to the way).
    --   -> the way shows 1950-2000 (the gap after the relation).
    --
    -- STEP 1: list the member ways with their own dates.
    -- STEP 2: clip each relation to the member way's dates.
    -- STEP 3: fill the periods no relation covers with the way itself.
    -- =======================================================================
    -- STEP 1 — member ways with their own life span (as decimal dates).
    mline_member_ways AS (
      SELECT DISTINCT
        tl.osm_id, tl.geometry, tl.highway, tl.type, tl.class,
        tl.tunnel, tl.bridge, tl.oneway, tl.ref, tl.z_order, tl.access, tl.service,
        tl.ford, tl.electrified, tl.highspeed, tl.usage, tl.street_running, tl.railway, tl.aeroway, tl.aerialway,
        tl.route, tl.expressway, tl.tags,
        isodatetodecimaldate(pad_date(tl.start_date, 'start'), FALSE) AS w_s,
        isodatetodecimaldate(pad_date(NULLIF(tl.end_date, ''), 'end'), FALSE) AS w_e
      FROM osm_transport_lines AS tl
      WHERE tl.geometry IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM osm_transport_multilines AS tm
          WHERE tm.member::bigint = tl.osm_id
            AND ST_GeometryType(tm.geometry) = 'ST_LineString'
        )
    ),
    -- STEP 2 — clip each relation to the member way's dates. GREATEST/LEAST
    -- keep only the overlap, so a relation never shows outside the way.
    -- (rel_*_dec keep the un-clipped dates, so we keep the original text when
    -- the clip did not actually move a boundary.)
    mline_rels_clipped AS (
      SELECT
        tm.id AS rel_id, tm.osm_id AS rel_osm_id, tm.member::bigint AS member_osm_id,
        tm.geometry, tm.highway, tm.type, tm.class, tm.name,
        tm.tunnel, tm.bridge, tm.oneway, tm.ref, tm.z_order, tm.access, tm.service,
        tm.ford, tm.electrified, tm.highspeed, tm.usage, tm.street_running, tm.railway, tm.aeroway, tm.aerialway,
        tm.route, tm.expressway, tm.tags,
        tm.start_date AS rel_start_date, NULLIF(tm.end_date, '') AS rel_end_date,
        isodatetodecimaldate(pad_date(tm.start_date, 'start'), FALSE) AS rel_s_dec,
        isodatetodecimaldate(pad_date(NULLIF(tm.end_date, ''), 'end'), FALSE) AS rel_e_dec,
        GREATEST(isodatetodecimaldate(pad_date(tm.start_date, 'start'), FALSE), mw.w_s)::double precision AS s_dec,
        LEAST(isodatetodecimaldate(pad_date(NULLIF(tm.end_date, ''), 'end'), FALSE), mw.w_e)::double precision AS e_dec
      FROM osm_transport_multilines AS tm
      -- LEFT JOIN, not INNER: a multilinestring relation can group UNTAGGED
      -- ways (geometry only, no highway) that are not in osm_transport_lines.
      -- For those, mw is NULL -> no clip -> the relation renders on its own dates.
      LEFT JOIN mline_member_ways AS mw ON mw.osm_id = tm.member::bigint
      WHERE ST_GeometryType(tm.geometry) = 'ST_LineString' AND tm.geometry IS NOT NULL
    ),
    -- STEP 3 — the periods no relation covers. range_agg joins the clipped
    -- relation ranges; we subtract them from the way's range, and each leftover
    -- piece renders the way itself.
    mline_gaps AS (
      SELECT
        mw.osm_id, mw.geometry, mw.highway, mw.type, mw.class,
        mw.tunnel, mw.bridge, mw.oneway, mw.ref, mw.z_order, mw.access, mw.service,
        mw.ford, mw.electrified, mw.highspeed, mw.usage, mw.street_running, mw.railway, mw.aeroway, mw.aerialway,
        mw.route, mw.expressway, mw.tags,
        lower(g)::double precision AS s_dec, upper(g)::double precision AS e_dec,
        row_number() OVER (PARTITION BY mw.osm_id ORDER BY lower(g)) AS gap_n
      FROM mline_member_ways AS mw
      CROSS JOIN LATERAL (
        SELECT unnest(
          -- Guard against bad data (start_date > end_date): an inverted way
          -- range would make numrange() throw and abort the whole mview. Such
          -- ways get no gap fill (their clipped relations still render).
          (CASE
             WHEN mw.w_s IS NOT NULL AND mw.w_e IS NOT NULL AND mw.w_s > mw.w_e
               THEN '{}'::nummultirange
             ELSE nummultirange(numrange(mw.w_s::numeric, mw.w_e::numeric))
           END)
          - COALESCE(range_agg(numrange(rc.s_dec::numeric, rc.e_dec::numeric)), '{}'::nummultirange)
        ) AS g
        FROM mline_rels_clipped AS rc
        WHERE rc.member_osm_id = mw.osm_id
          AND (rc.s_dec IS NULL OR rc.e_dec IS NULL OR rc.s_dec < rc.e_dec)
      ) AS gaps_expand
    ),
    -- =======================================================================
    -- STREET RELATIONS (osm_street_multilines) — fix #1320
    --
    -- Same 3 steps as the route block above, but for type=street relations.
    -- A street relation names/reclassifies the way for a time period; we clip
    -- it to the way's dates, and the way (with its OWN name) fills the rest.
    --
    -- Example: way "Old Road" 1900-2000. Street relation "New Ave" 1950-1980.
    --   -> "New Ave" shows 1950-1980. "Old Road" shows 1900-1950 and 1980-2000.
    --
    -- STEP 1: list the street-member ways with their own dates.
    -- STEP 2: clip each street relation to the member way's dates.
    -- STEP 3: fill the periods no street relation covers with the way itself.
    -- (Transport-multiline members are handled above, not here.)
    -- =======================================================================
    -- STEP 1 — street-member ways with their own attributes and dates. Only
    -- ways whose street relation changes something (attr_diff_pairs) are here;
    -- ways whose street relation changes nothing render as plain ways below.
    smember_ways AS (
      SELECT DISTINCT
        tl.osm_id, tl.geometry, tl.highway, tl.type, tl.class, tl.name AS way_name,
        tl.tunnel, tl.bridge, tl.oneway, tl.ref, tl.z_order, tl.access, tl.service,
        tl.ford, tl.electrified, tl.highspeed, tl.usage, tl.street_running, tl.railway, tl.aeroway, tl.aerialway,
        tl.route, tl.expressway, tl.tags,
        isodatetodecimaldate(pad_date(tl.start_date, 'start'), FALSE) AS w_s,
        isodatetodecimaldate(pad_date(NULLIF(tl.end_date, ''), 'end'), FALSE) AS w_e
      FROM osm_transport_lines AS tl
      WHERE tl.geometry IS NOT NULL
        AND EXISTS (SELECT 1 FROM attr_diff_pairs AS adp WHERE adp.way_osm_id = tl.osm_id)
        AND NOT EXISTS (
          SELECT 1 FROM osm_transport_multilines AS tm
          WHERE tm.member::bigint = tl.osm_id AND ST_GeometryType(tm.geometry) = 'ST_LineString'
        )
    ),
    -- STEP 2 — clip each street relation to the member way's dates. The
    -- relation's attributes (name, highway, ...) win over the way's; dates are
    -- clipped with GREATEST/LEAST. (rel_*_dec keep the un-clipped dates, so we
    -- keep the original text when the clip did not move a boundary.)
    smline_rels_clipped AS (
      SELECT
        sm.osm_id AS rel_osm_id, sm.member::bigint AS member_osm_id, mw.geometry,
        COALESCE(NULLIF(sm.highway, ''), mw.highway) AS highway,
        mw.type, mw.class,
        COALESCE(NULLIF(sm.name, ''), NULLIF(mw.way_name, '')) AS name,
        COALESCE(sm.tunnel, mw.tunnel) AS tunnel,
        COALESCE(sm.bridge, mw.bridge) AS bridge,
        COALESCE(sm.oneway, mw.oneway) AS oneway,
        COALESCE(NULLIF(sm.ref, ''), mw.ref) AS ref,
        COALESCE(sm.z_order, mw.z_order) AS z_order,
        COALESCE(NULLIF(sm.access, ''), mw.access) AS access,
        COALESCE(NULLIF(sm.service, ''), mw.service) AS service,
        COALESCE(NULLIF(sm.ford, ''), mw.ford) AS ford,
        COALESCE(NULLIF(sm.electrified, ''), mw.electrified) AS electrified,
        COALESCE(NULLIF(sm.highspeed, ''), mw.highspeed) AS highspeed,
        COALESCE(NULLIF(sm.usage, ''), mw.usage) AS usage,
        COALESCE(NULLIF(sm.street_running, ''), mw.street_running) AS street_running,
        COALESCE(NULLIF(sm.railway, ''), mw.railway) AS railway,
        COALESCE(NULLIF(sm.aeroway, ''), mw.aeroway) AS aeroway,
        COALESCE(NULLIF(sm.aerialway, ''), mw.aerialway) AS aerialway,
        COALESCE(NULLIF(sm.route, ''), mw.route) AS route,
        COALESCE(sm.expressway, mw.expressway) AS expressway,
        (sm.tags || mw.tags) AS tags,
        sm.start_date AS rel_start_date, NULLIF(sm.end_date, '') AS rel_end_date,
        isodatetodecimaldate(pad_date(sm.start_date, 'start'), FALSE) AS rel_s_dec,
        isodatetodecimaldate(pad_date(NULLIF(sm.end_date, ''), 'end'), FALSE) AS rel_e_dec,
        GREATEST(isodatetodecimaldate(pad_date(sm.start_date, 'start'), FALSE), mw.w_s)::double precision AS s_dec,
        LEAST(isodatetodecimaldate(pad_date(NULLIF(sm.end_date, ''), 'end'), FALSE), mw.w_e)::double precision AS e_dec
      FROM osm_street_multilines AS sm
      INNER JOIN smember_ways AS mw ON mw.osm_id = sm.member::bigint
      INNER JOIN attr_diff_pairs AS adp ON adp.way_osm_id = sm.member::bigint AND adp.rel_osm_id = sm.osm_id
      WHERE ST_GeometryType(sm.geometry) = 'ST_LineString' AND sm.geometry IS NOT NULL
    ),
    -- STEP 3 — the periods no street relation covers. Subtract the clipped
    -- relation ranges from the way's range; each leftover piece renders the
    -- way itself, keeping its own name.
    smline_gaps AS (
      SELECT
        mw.osm_id, mw.geometry, mw.highway, mw.type, mw.class, mw.way_name,
        mw.tunnel, mw.bridge, mw.oneway, mw.ref, mw.z_order, mw.access, mw.service,
        mw.ford, mw.electrified, mw.highspeed, mw.usage, mw.street_running, mw.railway, mw.aeroway, mw.aerialway,
        mw.route, mw.expressway, mw.tags,
        lower(g)::double precision AS s_dec, upper(g)::double precision AS e_dec,
        row_number() OVER (PARTITION BY mw.osm_id ORDER BY lower(g)) AS gap_n
      FROM smember_ways AS mw
      CROSS JOIN LATERAL (
        SELECT unnest(
          -- Guard against bad data (start_date > end_date): an inverted way
          -- range would make numrange() throw and abort the whole mview. Such
          -- ways get no gap fill (their clipped relations still render).
          (CASE
             WHEN mw.w_s IS NOT NULL AND mw.w_e IS NOT NULL AND mw.w_s > mw.w_e
               THEN '{}'::nummultirange
             ELSE nummultirange(numrange(mw.w_s::numeric, mw.w_e::numeric))
           END)
          - COALESCE(range_agg(numrange(rc.s_dec::numeric, rc.e_dec::numeric)), '{}'::nummultirange)
        ) AS g
        FROM smline_rels_clipped AS rc
        WHERE rc.member_osm_id = mw.osm_id
          AND (rc.s_dec IS NULL OR rc.e_dec IS NULL OR rc.s_dec < rc.e_dec)
      ) AS gaps_expand
    ),
    combined AS (
      -- -------------------------------------------------------------------
      -- Plain ways — no attribute-changing street relation. Street-member
      -- ways are handled by the clip + gap branches below.
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
        NULLIF(tags->'golf', '') AS golf,
        class,
        NULLIF(name, '') AS name,
        NULLIF(tunnel, 0) AS tunnel,
        NULLIF(bridge, 0) AS bridge,
        NULLIF(oneway, 0) AS oneway,
        NULLIF(ref, '') AS ref,
        z_order,
        NULLIF(access, '') AS access,
        NULLIF(service, '') AS service,
        NULLIF(ford, '') AS ford,
        NULLIF(electrified, '') AS electrified,
        NULLIF(highspeed, '') AS highspeed,
        NULLIF(usage, '') AS usage,
        NULLIF(street_running, '') AS street_running,
        NULLIF(railway, '') AS railway,
        NULLIF(aeroway, '') AS aeroway,
        NULLIF(aerialway, '') AS aerialway,
        NULLIF(highway, '') AS highway,
        NULLIF(route, '') AS route,
        NULLIF(expressway, 0) AS expressway,
        NULLIF(start_date, '') AS start_date,
        NULLIF(end_date, '') AS end_date,
        isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
        isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
        tags,
        ABS(street_rel_osm_id) AS relation,
        'way' AS source_type,
        %s
      FROM plain_ways

      UNION ALL

      -- -------------------------------------------------------------------
      -- #1320 Part 1 — Transport/route/street relation members, CLIPPED to the
      -- member way's date range so nothing renders outside the way's life span.
      -- -------------------------------------------------------------------
      SELECT
        (COALESCE(CAST(rel_id AS TEXT), '') || '_' || COALESCE(CAST(rel_osm_id AS TEXT), '')) AS id,
        ABS(member_osm_id) AS osm_id,
        geometry,
        CASE
            WHEN highway = 'construction' THEN
                COALESCE(NULLIF(tags->'construction', '') || '_construction', 'road_construction')
            ELSE type
        END AS type,
        NULLIF(tags->'construction', '') AS construction,
        NULLIF(tags->'golf', '') AS golf,
        class,
        NULLIF(name, '') AS name,
        NULLIF(tunnel, 0) AS tunnel,
        NULLIF(bridge, 0) AS bridge,
        NULLIF(oneway, 0) AS oneway,
        NULLIF(ref, '') AS ref,
        z_order,
        NULLIF(access, '') AS access,
        NULLIF(service, '') AS service,
        NULLIF(ford, '') AS ford,
        NULLIF(electrified, '') AS electrified,
        NULLIF(highspeed, '') AS highspeed,
        NULLIF(usage, '') AS usage,
        NULLIF(street_running, '') AS street_running,
        NULLIF(railway, '') AS railway,
        NULLIF(aeroway, '') AS aeroway,
        NULLIF(aerialway, '') AS aerialway,
        NULLIF(highway, '') AS highway,
        NULLIF(route, '') AS route,
        NULLIF(expressway, 0) AS expressway,
        -- Keep the original relation text when the clip did not move the
        -- boundary; convert from the clipped decimal only when it did.
        CASE WHEN s_dec IS DISTINCT FROM rel_s_dec THEN NULLIF(decimaldatetoisodate(s_dec), '')
             ELSE NULLIF(rel_start_date, '') END AS start_date,
        CASE WHEN e_dec IS DISTINCT FROM rel_e_dec
             THEN CASE WHEN e_dec IS NULL THEN NULL ELSE NULLIF(decimaldatetoisodate(e_dec), '') END
             ELSE rel_end_date END AS end_date,
        s_dec AS start_decdate,
        e_dec AS end_decdate,
        tags,
        ABS(rel_osm_id) AS relation,
        'relation' AS source_type,
        %s
      FROM mline_rels_clipped
      WHERE (s_dec IS NULL OR e_dec IS NULL OR s_dec < e_dec)

      UNION ALL

      -- -------------------------------------------------------------------
      -- #1320 Part 2 (gap-fill) — the member way itself, for periods not
      -- covered by any relation, so the road stays visible across its full
      -- life span. Remove this UNION ALL block to ship Part 1 only.
      -- -------------------------------------------------------------------
      SELECT
        (COALESCE(CAST(osm_id AS TEXT), '') || '_gap_' || gap_n::text) AS id,
        ABS(osm_id) AS osm_id,
        geometry,
        CASE
            WHEN highway = 'construction' THEN
                COALESCE(NULLIF(tags->'construction', '') || '_construction', 'road_construction')
            ELSE type
        END AS type,
        NULLIF(tags->'construction', '') AS construction,
        NULLIF(tags->'golf', '') AS golf,
        class,
        NULL::text AS name,
        NULLIF(tunnel, 0) AS tunnel,
        NULLIF(bridge, 0) AS bridge,
        NULLIF(oneway, 0) AS oneway,
        NULLIF(ref, '') AS ref,
        z_order,
        NULLIF(access, '') AS access,
        NULLIF(service, '') AS service,
        NULLIF(ford, '') AS ford,
        NULLIF(electrified, '') AS electrified,
        NULLIF(highspeed, '') AS highspeed,
        NULLIF(usage, '') AS usage,
        NULLIF(street_running, '') AS street_running,
        NULLIF(railway, '') AS railway,
        NULLIF(aeroway, '') AS aeroway,
        NULLIF(aerialway, '') AS aerialway,
        NULLIF(highway, '') AS highway,
        NULLIF(route, '') AS route,
        NULLIF(expressway, 0) AS expressway,
        CASE WHEN s_dec IS NULL THEN NULL ELSE NULLIF(decimaldatetoisodate(s_dec), '') END AS start_date,
        CASE WHEN e_dec IS NULL THEN NULL ELSE NULLIF(decimaldatetoisodate(e_dec), '') END AS end_date,
        s_dec AS start_decdate,
        e_dec AS end_decdate,
        tags,
        NULL::bigint AS relation,
        'way' AS source_type,
        %s
      FROM mline_gaps

      UNION ALL

      -- -------------------------------------------------------------------
      -- #1320 Part 1 (street) — street relation members, CLIPPED to the
      -- member way's date range.
      -- -------------------------------------------------------------------
      SELECT
        (COALESCE(CAST(rel_osm_id AS TEXT), '') || '_' || COALESCE(CAST(member_osm_id AS TEXT), '')) AS id,
        ABS(member_osm_id) AS osm_id,
        geometry,
        CASE
            WHEN highway = 'construction' THEN
                COALESCE(NULLIF(tags->'construction', '') || '_construction', 'road_construction')
            ELSE type
        END AS type,
        NULLIF(tags->'construction', '') AS construction,
        NULLIF(tags->'golf', '') AS golf,
        class,
        NULLIF(name, '') AS name,
        NULLIF(tunnel, 0) AS tunnel,
        NULLIF(bridge, 0) AS bridge,
        NULLIF(oneway, 0) AS oneway,
        NULLIF(ref, '') AS ref,
        z_order,
        NULLIF(access, '') AS access,
        NULLIF(service, '') AS service,
        NULLIF(ford, '') AS ford,
        NULLIF(electrified, '') AS electrified,
        NULLIF(highspeed, '') AS highspeed,
        NULLIF(usage, '') AS usage,
        NULLIF(street_running, '') AS street_running,
        NULLIF(railway, '') AS railway,
        NULLIF(aeroway, '') AS aeroway,
        NULLIF(aerialway, '') AS aerialway,
        NULLIF(highway, '') AS highway,
        NULLIF(route, '') AS route,
        NULLIF(expressway, 0) AS expressway,
        CASE WHEN s_dec IS DISTINCT FROM rel_s_dec THEN NULLIF(decimaldatetoisodate(s_dec), '')
             ELSE NULLIF(rel_start_date, '') END AS start_date,
        CASE WHEN e_dec IS DISTINCT FROM rel_e_dec
             THEN CASE WHEN e_dec IS NULL THEN NULL ELSE NULLIF(decimaldatetoisodate(e_dec), '') END
             ELSE rel_end_date END AS end_date,
        s_dec AS start_decdate,
        e_dec AS end_decdate,
        tags,
        ABS(rel_osm_id) AS relation,
        'way' AS source_type,
        %s
      FROM smline_rels_clipped
      WHERE (s_dec IS NULL OR e_dec IS NULL OR s_dec < e_dec)

      UNION ALL

      -- -------------------------------------------------------------------
      -- #1320 Part 2 (street gap-fill) — the member way itself (with its own
      -- name) for periods not covered by any street relation.
      -- -------------------------------------------------------------------
      SELECT
        (COALESCE(CAST(osm_id AS TEXT), '') || '_sgap_' || gap_n::text) AS id,
        ABS(osm_id) AS osm_id,
        geometry,
        CASE
            WHEN highway = 'construction' THEN
                COALESCE(NULLIF(tags->'construction', '') || '_construction', 'road_construction')
            ELSE type
        END AS type,
        NULLIF(tags->'construction', '') AS construction,
        NULLIF(tags->'golf', '') AS golf,
        class,
        NULLIF(way_name, '') AS name,
        NULLIF(tunnel, 0) AS tunnel,
        NULLIF(bridge, 0) AS bridge,
        NULLIF(oneway, 0) AS oneway,
        NULLIF(ref, '') AS ref,
        z_order,
        NULLIF(access, '') AS access,
        NULLIF(service, '') AS service,
        NULLIF(ford, '') AS ford,
        NULLIF(electrified, '') AS electrified,
        NULLIF(highspeed, '') AS highspeed,
        NULLIF(usage, '') AS usage,
        NULLIF(street_running, '') AS street_running,
        NULLIF(railway, '') AS railway,
        NULLIF(aeroway, '') AS aeroway,
        NULLIF(aerialway, '') AS aerialway,
        NULLIF(highway, '') AS highway,
        NULLIF(route, '') AS route,
        NULLIF(expressway, 0) AS expressway,
        CASE WHEN s_dec IS NULL THEN NULL ELSE NULLIF(decimaldatetoisodate(s_dec), '') END AS start_date,
        CASE WHEN e_dec IS NULL THEN NULL ELSE NULLIF(decimaldatetoisodate(e_dec), '') END AS end_date,
        s_dec AS start_decdate,
        e_dec AS end_decdate,
        tags,
        NULL::bigint AS relation,
        'way' AS source_type,
        %s
      FROM smline_gaps
    )
    SELECT DISTINCT ON (id) *
    FROM combined;
  $sql$, lang_columns, lang_columns, lang_columns, lang_columns, lang_columns);

  PERFORM finalize_materialized_view(
    'mv_transport_lines_z16_20_tmp',
    'mv_transport_lines_z16_20',
    'id',
    sql_create
  );
END;
$do$;


SELECT derive_line_mview(
    source           => 'mv_transport_lines_z16_20',
    target           => 'mv_transport_lines_z13_15',
    simplify_tol     => 5,
    where_filter     => 'type IN (''motorway'', ''motorway_link'', ''trunk'', ''trunk_link'', ''construction'', ''primary'', ''primary_link'', ''rail'', ''secondary'', ''secondary_link'', ''tertiary'', ''tertiary_link'', ''miniature'', ''narrow_gauge'', ''dismantled'', ''abandoned'', ''disused'', ''razed'', ''light_rail'', ''preserved'', ''proposed'', ''tram'', ''funicular'', ''monorail'', ''taxiway'', ''runway'', ''raceway'', ''residential'', ''service'', ''unclassified'', ''ferry'', ''track'', ''path'', ''footway'', ''cycleway'', ''pedestrian'', ''living_street'', ''steps'', ''bridleway'') OR class IN (''railway'', ''aerialway'')'
);
SELECT derive_line_mview(
    source           => 'mv_transport_lines_z13_15',
    target           => 'mv_transport_lines_z10_12',
    simplify_tol     => 20,
    where_filter     => 'type IN (''motorway'', ''motorway_link'', ''trunk'', ''trunk_link'', ''construction'', ''primary'', ''primary_link'', ''rail'', ''secondary'', ''secondary_link'', ''tertiary'', ''tertiary_link'', ''miniature'', ''narrow_gauge'', ''dismantled'', ''abandoned'', ''disused'', ''razed'', ''light_rail'', ''preserved'', ''proposed'', ''tram'', ''funicular'', ''monorail'', ''taxiway'', ''runway'', ''ferry'') OR class IN (''railway'')'
);
SELECT derive_line_mview(
    source           => 'mv_transport_lines_z10_12',
    target           => 'mv_transport_lines_z8_9',
    simplify_tol     => 100
);
SELECT derive_line_mview(
    source           => 'mv_transport_lines_z8_9',
    target           => 'mv_transport_lines_z6_7',
    simplify_tol     => 200,
    where_filter     => 'type IN (''motorway'', ''motorway_link'', ''trunk'', ''trunk_link'', ''construction'', ''primary'', ''primary_link'', ''rail'', ''secondary'', ''secondary_link'', ''ferry'') OR class IN (''railway'')'
);
SELECT derive_line_mview(
    source           => 'mv_transport_lines_z6_7',
    target           => 'mv_transport_lines_z5',
    simplify_tol     => 1000
);
-- Refresh lines views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_lines_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_lines_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_lines_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_lines_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_lines_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_lines_z5;
