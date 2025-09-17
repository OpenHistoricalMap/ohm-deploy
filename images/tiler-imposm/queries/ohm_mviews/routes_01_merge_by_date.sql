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

CREATE MATERIALIZED VIEW mv_routes_normalized AS
WITH union_sources AS (
  -- 1) Get from multi-lines (osm_route_multilines)
  SELECT
    member::bigint AS way_id,
    osm_id,
    name,
    type,
    route,
    ref,
    network,
    operator,
    direction,
    tags,
    geometry,
    start_decdate,
    end_decdate
  FROM osm_route_multilines
  WHERE geometry IS NOT NULL

  UNION ALL

  -- 2) Get from lines (osm_route_lines)
  SELECT
    osm_id::bigint AS way_id,
    osm_id,
    name,
    type,
    route,
    ref,
    network,
    operator,
    direction,
    tags,
    geometry,
    start_decdate,
    end_decdate
  FROM osm_route_lines
  WHERE geometry IS NOT NULL
),
dates AS (
  -- Collect all the date cutoffs by way.
  SELECT way_id, start_decdate AS d FROM union_sources
  UNION
  SELECT way_id, end_decdate FROM union_sources WHERE end_decdate IS NOT NULL
),
ordered AS (
  SELECT way_id, d
  FROM dates
  WHERE d IS NOT NULL
  GROUP BY way_id, d
),
segments AS (
  -- Form consecutive time segments
  SELECT 
    way_id,
    d AS seg_start,
    LEAD(d) OVER (PARTITION BY way_id ORDER BY d) AS seg_end
  FROM ordered
),
active AS (
  -- Allocate active routes to each segment.
  SELECT
    s.way_id,
    s.seg_start,
    s.seg_end,
    u.osm_id,
    u.ref,
    u.route,
    u.network,
    u.name,
    u.type,
    u.operator,
    u.direction,
    u.tags,
    u.geometry
  FROM segments s
  JOIN union_sources u
    ON u.way_id = s.way_id
   AND u.start_decdate <= COALESCE(s.seg_start, u.end_decdate)
   AND (u.end_decdate IS NULL OR u.end_decdate > s.seg_start)
)
SELECT
  row_number() OVER () AS uid,
  way_id,
  seg_start AS min_start_decdate,
  seg_end   AS max_end_decdate,
  convert_decimal_to_iso_date(seg_start::NUMERIC) AS min_start_date_iso,
  convert_decimal_to_iso_date(seg_end::NUMERIC)   AS max_end_date_iso,

  -- Unique geometry (first one)
  (ARRAY_AGG(geometry))[1] AS geometry,

   -- Count of distinct routes (osm_id)
  COUNT(DISTINCT osm_id) AS num_routes,
  
  -- Concurrent routes valid in that time range
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
  ) AS routes

FROM active
GROUP BY way_id, seg_start, seg_end
ORDER BY way_id, seg_start
WITH DATA;


-- ===============================
-- Indexes
-- ===============================

-- Drop indexes if they exist
DROP INDEX IF EXISTS mv_routes_normalized_unique_idx;
DROP INDEX IF EXISTS mv_routes_normalized_way_idx;
DROP INDEX IF EXISTS mv_routes_normalized_dates_idx;
DROP INDEX IF EXISTS mv_routes_normalized_geom_idx;

-- Mandatory UNIQUE index (required by PostgreSQL for REFRESH CONCURRENTLY)
CREATE UNIQUE INDEX mv_routes_normalized_unique_idx 
ON mv_routes_normalized (uid);

-- Supporting indexes for faster queries
CREATE INDEX mv_routes_normalized_way_idx 
ON mv_routes_normalized (way_id);

CREATE INDEX mv_routes_normalized_dates_idx 
ON mv_routes_normalized (min_start_decdate, max_end_decdate);

CREATE INDEX mv_routes_normalized_geom_idx 
ON mv_routes_normalized USING GIST (geometry);

-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_routes_normalized;