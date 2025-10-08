-- ============================================================================
-- STEP 1: Add New Columns
-- ============================================================================

--- osm_route_multilines
SELECT log_notice('STEP 1: Adding new columns in osm_route_multilines table');
ALTER TABLE osm_route_multilines
ADD COLUMN start_decdate DOUBLE PRECISION,
ADD COLUMN end_decdate DOUBLE PRECISION;

--- osm_route_lines
SELECT log_notice('STEP 1: Adding new columns in osm_route_lines table');
ALTER TABLE osm_route_lines
ADD COLUMN start_decdate DOUBLE PRECISION,
ADD COLUMN end_decdate DOUBLE PRECISION;


-- ============================================================================
-- STEP 2: Trigger to auto-fill start_decdate / end_decdate
-- (reutilizar la misma función `convert_dates_to_decimal()` que ya tienes)
-- ============================================================================

--- osm_route_multilines
CREATE TRIGGER trigger_decimal_dates_osm_route_multilines
BEFORE INSERT OR UPDATE 
ON osm_route_multilines
FOR EACH ROW
EXECUTE FUNCTION convert_dates_to_decimal();

--- osm_route_lines
CREATE TRIGGER trigger_decimal_dates_osm_route_lines
BEFORE INSERT OR UPDATE 
ON osm_route_lines
FOR EACH ROW
EXECUTE FUNCTION convert_dates_to_decimal();


-- ============================================================================
-- STEP 3: Backfill Existing Data
-- ============================================================================

--- osm_route_multilines
SELECT log_notice('STEP 3: Backfill for osm_route_multilines');

SET statement_timeout = 2400000;
UPDATE osm_route_multilines
SET start_decdate = isodatetodecimaldate(pad_date(start_date::TEXT, 'start')::TEXT, FALSE),
    end_decdate = isodatetodecimaldate(pad_date(end_date::TEXT, 'end')::TEXT, FALSE)
WHERE ST_GeometryType(geometry) IN ('ST_LineString', 'ST_MultiLineString');


--- osm_route_lines
SET statement_timeout = 2400000;
UPDATE osm_route_lines
SET start_decdate = isodatetodecimaldate(pad_date(start_date::TEXT, 'start')::TEXT, FALSE),
    end_decdate   = isodatetodecimaldate(pad_date(end_date::TEXT, 'end')::TEXT, FALSE)
WHERE ST_GeometryType(geometry) IN ('ST_LineString', 'ST_MultiLineString');

-- ============================================================================
-- STEP 4: Create Materialized View for merged routes per continuous temporal range
-- ============================================================================
SELECT log_notice('STEP 4: Merged routes materialized view');

DROP MATERIALIZED VIEW IF EXISTS mv_routes_normalized CASCADE;

DROP MATERIALIZED VIEW IF EXISTS mv_routes_normalized CASCADE;

CREATE MATERIALIZED VIEW mv_routes_normalized AS
WITH union_sources AS (
  -- 1) From multi-lines (relations with members)
  SELECT
    member::bigint AS way_id,
    osm_id, name, type, route, ref, network, operator, direction, tags, geometry,
    start_decdate,
    end_decdate
  FROM osm_route_multilines
  WHERE geometry IS NOT NULL

  UNION ALL

  -- 2) From lines (direct way-based routes)
  SELECT
    osm_id::bigint AS way_id,
    osm_id, name, type, route, ref, network, operator, direction, tags, geometry,
    start_decdate,
    end_decdate
  FROM osm_route_lines
  WHERE geometry IS NOT NULL
),
-- CTE to identify ways that DO have at least one date
ways_with_dates AS (
  SELECT DISTINCT way_id
  FROM union_sources
  WHERE start_decdate IS NOT NULL OR end_decdate IS NOT NULL
),
-- CASE 1: Process ways that DO NOT have dates. We assume a single "infinite" period.
data_for_null_dates AS (
  SELECT
    u.way_id,
    -- NULL::text AS direction,                        -- position 2
    NULL::double precision AS min_start_decdate,    -- position 3
    NULL::double precision AS max_end_decdate,      -- position 4
    NULL::text AS min_start_date_iso,               -- position 5
    NULL::text AS max_end_date_iso,                 -- position 6
    (ARRAY_AGG(u.geometry))[1] AS geometry,         -- position 7
    COUNT(DISTINCT u.osm_id) AS num_routes,         -- position 8
    jsonb_agg(
      jsonb_build_object(
        'osm_id', u.osm_id,
        'ref', u.ref,
        'route', u.route, 
        'network', u.network,
        'name', u.name, 
        'type', u.type, 
        'operator', u.operator, 
        'direction', u.direction, 
        'tags', u.tags
      )
      ORDER BY u.ref
    ) AS routes                                     -- position 9
  FROM union_sources u
  WHERE u.way_id NOT IN (SELECT way_id FROM ways_with_dates)
  GROUP BY u.way_id
),
-- CASE 2: Process ways that DO have dates, using segmentation logic.
data_for_dated_ways AS (
  WITH dates AS (
    SELECT way_id, start_decdate AS d 
    FROM union_sources 
    WHERE way_id IN (SELECT way_id FROM ways_with_dates) AND start_decdate IS NOT NULL
    UNION
    SELECT way_id, end_decdate 
    FROM union_sources 
    WHERE way_id IN (SELECT way_id FROM ways_with_dates) AND end_decdate IS NOT NULL
  ),
  ordered AS (
    -- Deduplicate and order cut-off dates per way
    SELECT way_id, d FROM dates GROUP BY way_id, d
  ),
  segments AS (
    -- Build consecutive segments by pairing each cutoff with the next (LEAD)
    SELECT 
      way_id,
      d AS seg_start,
      LEAD(d) OVER (PARTITION BY way_id ORDER BY d) AS seg_end
    FROM ordered
  ),
  active AS (
    -- Relate active routes to each time segment
    SELECT
      s.way_id, s.seg_start, s.seg_end,
      u.osm_id, u.ref, u.route, u.network, u.name, u.type, u.operator, u.direction, u.tags, u.geometry
    FROM segments s
    JOIN union_sources u
      ON u.way_id = s.way_id
     AND (u.start_decdate IS NULL OR u.start_decdate < COALESCE(s.seg_end, 9999)) -- active before segment end
     AND (u.end_decdate   IS NULL OR u.end_decdate   > s.seg_start)              -- active after segment start
  ),
  base AS (
    -- Group active routes by way_id, segment and direction to build base records
    SELECT
      way_id,
      seg_start AS min_start_decdate,
      seg_end   AS max_end_decdate,
      convert_decimal_to_iso_date(seg_start::NUMERIC) AS min_start_date_iso,
      convert_decimal_to_iso_date(seg_end::NUMERIC)   AS max_end_date_iso,
      -- direction,
      (ARRAY_AGG(geometry))[1] AS geometry,
      COUNT(DISTINCT osm_id) AS num_routes,
      jsonb_agg(
        jsonb_build_object(
          'osm_id', osm_id, 
          'ref', ref, 
          'route', route, 
          'network', network, 
          'name', name,
          'type', type, 
          'operator', operator, 
          'direction', direction, 
          'tags', tags
        )
        ORDER BY ref
      ) AS routes,
      md5(array_to_string(ARRAY_AGG(DISTINCT osm_id ORDER BY osm_id), ',')) AS routeset_hash
    FROM active
    GROUP BY way_id, seg_start, seg_end
  ),
  merged AS (
    -- Merge adjacent segments that share the same routeset_hash and direction (gap <= 1 day)
    SELECT 
      way_id,
      MIN(min_start_decdate) AS min_start_decdate,
      MAX(max_end_decdate)   AS max_end_decdate,
      MIN(min_start_date_iso) AS min_start_date_iso,
      MAX(max_end_date_iso)   AS max_end_date_iso,
      (ARRAY_AGG(geometry))[1] AS geometry,
      MAX(num_routes) AS num_routes,
      (ARRAY_AGG(routes))[1] AS routes,
      routeset_hash
    FROM (
      SELECT 
        t.*,
        SUM(is_new_group) OVER (
          PARTITION BY way_id, routeset_hash 
          ORDER BY min_start_decdate
        ) AS grp
      FROM (
        SELECT *,
               CASE 
                 -- Start a new group if there is no previous segment or if gap > 1 day
                 WHEN LAG(max_end_decdate) OVER (
                        PARTITION BY way_id, routeset_hash 
                        ORDER BY min_start_decdate
                 ) IS NULL THEN 1
                 WHEN min_start_decdate - LAG(max_end_decdate) OVER (
                        PARTITION BY way_id, routeset_hash 
                        ORDER BY min_start_decdate
                 ) > (1.0/365.0) THEN 1
                 ELSE 0
               END AS is_new_group
        FROM base
      ) t
    ) g
    GROUP BY way_id, grp, routeset_hash
  )
  SELECT 
    way_id, 
    min_start_decdate, 
    max_end_decdate, 
    min_start_date_iso, 
    max_end_date_iso, 
    geometry, 
    num_routes, 
    routes
  FROM merged
)
-- Combine the two result sets
SELECT 
  row_number() OVER () AS uid,
  t.*
FROM (
  SELECT * FROM data_for_dated_ways
  UNION ALL
  SELECT * FROM data_for_null_dates
) t
ORDER BY way_id, min_start_decdate
WITH DATA;

-- ===============================
-- Indexes (no changes)
-- ===============================
DROP INDEX IF EXISTS mv_routes_normalized_unique_idx;
DROP INDEX IF EXISTS mv_routes_normalized_way_idx;
DROP INDEX IF EXISTS mv_routes_normalized_dates_idx;
DROP INDEX IF EXISTS mv_routes_normalized_geom_idx;

CREATE UNIQUE INDEX mv_routes_normalized_unique_idx 
ON mv_routes_normalized (uid);

CREATE INDEX mv_routes_normalized_way_idx 
ON mv_routes_normalized (way_id);

CREATE INDEX mv_routes_normalized_dates_idx 
ON mv_routes_normalized (min_start_decdate, max_end_decdate);

CREATE INDEX mv_routes_normalized_geom_idx 
ON mv_routes_normalized USING GIST (geometry);

-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_routes_normalized;
165889