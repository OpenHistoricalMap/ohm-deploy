-- This script creates materialized views for admin boundaries (lines) conbined from tables osm_relation_members_boundaries and osm_admin_lines

-- ============================================================================
--STEP 1: Add New Columns in osm_relation_members_boundaries and osm_admin_lines
-- ============================================================================
DO $$ BEGIN RAISE NOTICE 'STEP 1: Adding new columns in osm_relation_members_boundaries and osm_admin_lines table'; END; $$;
ALTER TABLE osm_relation_members_boundaries 
ADD COLUMN start_decdate DOUBLE PRECISION,
ADD COLUMN end_decdate DOUBLE PRECISION;

ALTER TABLE osm_admin_lines 
ADD COLUMN start_decdate DOUBLE PRECISION,
ADD COLUMN end_decdate DOUBLE PRECISION;


-- ============================================================================
-- STEP 2: Create the Trigger, which will call the function above
-- ============================================================================
DO $$ BEGIN RAISE NOTICE 'STEP 2: Create trigger to convert date to decimal for new/updated objects in osm_relation_members_boundaries and osm_admin_lines table'; END; $$;
CREATE TRIGGER trigger_decimal_dates_osm_relation_members_boundaries 
BEFORE INSERT OR UPDATE 
ON osm_relation_members_boundaries
FOR EACH ROW
EXECUTE FUNCTION convert_dates_to_decimal();


CREATE TRIGGER trigger_decimal_dates_osm_admin_lines
BEFORE INSERT OR UPDATE 
ON osm_admin_lines
FOR EACH ROW
EXECUTE FUNCTION convert_dates_to_decimal();


-- ============================================================================
-- STEP 3: Backfill Existing Data, Set timeout to 40 minutes (2400000 milliseconds) for the current session, this takes quite a while, sincecurrnelty thrre are ~5 million rows in the table
-- ============================================================================
-- DO $$ BEGIN RAISE NOTICE 'STEP 3: Backfill existing data for osm_relation_members_boundaries table'; END; $$;
-- SET statement_timeout = 2400000;
-- UPDATE osm_relation_members_boundaries
-- SET start_decdate = isodatetodecimaldate(pad_date(start_date::TEXT, 'start')::TEXT, FALSE),
--     end_decdate = isodatetodecimaldate(pad_date(end_date::TEXT, 'end')::TEXT, FALSE)
-- WHERE ST_GeometryType(geometry) = 'ST_LineString';


-- DO $$ BEGIN RAISE NOTICE 'STEP 3: Backfill existing data for osm_admin_lines table'; END; $$;
-- SET statement_timeout = 2400000;
-- UPDATE osm_admin_lines
-- SET start_decdate = isodatetodecimaldate(pad_date(start_date::TEXT, 'start')::TEXT, FALSE),
--     end_decdate = isodatetodecimaldate(pad_date(end_date::TEXT, 'end')::TEXT, FALSE)
-- WHERE ST_GeometryType(geometry) = 'ST_LineString';


-- ============================================================================
-- STEP 4: Create a materialized view that merges lines based on start_decdate and end_decdate, admin_level, member and type
-- ============================================================================
DO $$ BEGIN RAISE NOTICE 'STEP 4: Create a materialized view that merges lines based on start_decdate and end_decdate using osm_relation_members_boundaries table'; END; $$;

DROP MATERIALIZED VIEW IF EXISTS mv_relation_members_boundaries CASCADE;

CREATE MATERIALIZED VIEW mv_relation_members_boundaries AS
WITH ordered AS (
  SELECT
    type,
    admin_level,
    member,
    geometry, 
    start_decdate,  
    end_decdate,
    LAG(end_decdate) OVER (
      PARTITION BY admin_level, member, type  
      ORDER BY start_decdate NULLS FIRST
    ) AS prev_end
  FROM osm_relation_members_boundaries
  WHERE ST_GeometryType(geometry) = 'ST_LineString'
    AND geometry IS NOT NULL
),

flagged AS (
  SELECT
    type,
    admin_level,
    member,
    geometry,
    start_decdate,  
    end_decdate,   
    CASE 
        WHEN prev_end IS NULL THEN 0 
        WHEN start_decdate IS NULL THEN 0
        WHEN 
            -- 0.003 covers all possible decimal gaps that correspond to one day (whether it’s a leap year or not).
            (start_decdate - prev_end) < 0.003
        THEN 0 -- No gap, merge
        ELSE 1 -- Gap exists
    END AS gap_flag
  FROM ordered
),

grouped AS (
  SELECT
    type,
    admin_level,
    member,
    geometry,
    start_decdate,  
    end_decdate,
    SUM(gap_flag) OVER (
      PARTITION BY admin_level, member, type  
      ORDER BY start_decdate NULLS FIRST
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS group_id
  FROM flagged
)

SELECT
  type,
  admin_level,
  member,
  group_id,
  (ARRAY_AGG(geometry ORDER BY start_decdate NULLS FIRST))[1] AS geometry,
  COUNT(*) AS merged_row_count,

  -- Keep the original decimal dates
  CASE 
      WHEN BOOL_OR(start_decdate IS NULL) THEN NULL 
      ELSE MIN(start_decdate) 
  END AS min_start_decdate,
  
  -- Ensure NULL propagation for end_decdate
  CASE 
      WHEN BOOL_OR(end_decdate IS NULL) THEN NULL 
      ELSE MAX(end_decdate) 
  END AS max_end_decdate,

  -- Convert the decimal dates to ISO format in separate columns
  convert_decimal_to_iso_date(
      CASE 
          WHEN BOOL_OR(start_decdate IS NULL) THEN NULL 
          ELSE MIN(start_decdate) 
      END::NUMERIC
  ) AS min_start_date_iso,
  
  convert_decimal_to_iso_date(
      CASE 
          WHEN BOOL_OR(end_decdate IS NULL) THEN NULL 
          ELSE MAX(end_decdate) 
      END::NUMERIC
  ) AS max_end_date_iso
     
FROM grouped
GROUP BY 
  type, admin_level, member, group_id
WITH DATA;

-- Drop indexes if exist
DROP INDEX IF EXISTS mview_admin_boundaries_idx;
DROP INDEX IF EXISTS mview_admin_boundaries_geometry_idx;

-- Create indexes for performance
CREATE UNIQUE INDEX mview_admin_boundaries_idx 
ON mv_relation_members_boundaries (admin_level, member, type, group_id);

CREATE INDEX mview_admin_boundaries_geometry_idx 
ON mv_relation_members_boundaries USING GIST (geometry);


-- ============================================================================
-- STEP 5: Create a materialized view that combines the data from mv_relation_members_boundaries and osm_admin_lines
-- ============================================================================
DO $$ BEGIN RAISE NOTICE 'STEP 5: Create a materialized view that combines the data from mv_relation_members_boundaries and osm_admin_lines'; END; $$;

DROP MATERIALIZED VIEW IF EXISTS mv_admin_boundaries_relations_ways CASCADE;

CREATE MATERIALIZED VIEW mv_admin_boundaries_relations_ways AS
WITH relation_boundaries AS (
  SELECT
    type,
    admin_level,
    member,
    geometry,
    group_id,
    min_start_decdate AS start_decdate,
    max_end_decdate AS end_decdate,
    min_start_date_iso AS start_date,
    max_end_date_iso AS end_date
  FROM mv_relation_members_boundaries
),
way_boundaries AS (
  SELECT
    type,
    admin_level,
    osm_id AS member,
    geometry,
    0 AS group_id,
    start_date,
    end_date,
    start_decdate, 
    end_decdate
  FROM osm_admin_lines
  WHERE type = 'administrative'
    AND osm_id NOT IN (SELECT member FROM mv_relation_members_boundaries) 
)
-- Join the two tables
SELECT 
  type,
  admin_level,
  member,
  geometry,
  group_id,
  start_decdate,
  end_decdate,
  start_date,
  end_date
FROM relation_boundaries

UNION ALL

SELECT 
  type,
  admin_level,
  member,
  geometry,
  group_id,
  start_decdate,
  end_decdate,
  start_date,
  end_date
FROM way_boundaries
WITH DATA;

-- Drop indexes if exist
DROP INDEX IF EXISTS mv_admin_boundaries_relations_ways_idx;
DROP INDEX IF EXISTS mv_admin_boundaries_relations_ways_geometry_idx;

-- Create indexs
CREATE UNIQUE INDEX mv_admin_boundaries_relations_ways_idx 
ON mv_admin_boundaries_relations_ways (admin_level, member, group_id);

CREATE INDEX mv_admin_boundaries_relations_ways_geometry_idx 
ON mv_admin_boundaries_relations_ways USING GIST (geometry);

-- ============================================================================
-- Execute force creation of all admin boundaries lines materialized views
-- ============================================================================
DO $$ BEGIN RAISE NOTICE 'STEP 6: Create a materialized view for zoom levels'; END; $$;


-- ==========================================
-- MViews for admin lines zoom 0-2
-- ==========================================
DROP MATERIALIZED VIEW IF EXISTS mv_admin_boundaries_lines_z0_2 CASCADE;
CREATE MATERIALIZED VIEW mv_admin_boundaries_lines_z0_2 AS
SELECT 
    type,
    admin_level,
    member,
    ST_SimplifyPreserveTopology(geometry, 5000) AS geometry,
    group_id,
    start_decdate,
    end_decdate,
    start_date,
    end_date
FROM mv_admin_boundaries_relations_ways
WHERE admin_level IN (1,2)
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z0_2_idx 
ON mv_admin_boundaries_lines_z0_2 (admin_level, member, group_id);

CREATE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z0_2_geometry_idx 
ON mv_admin_boundaries_lines_z0_2 USING GIST (geometry);

-- ==========================================
-- MViews for admin lines zoom 3-5
-- ==========================================
DROP MATERIALIZED VIEW IF EXISTS mv_admin_boundaries_lines_z3_5 CASCADE;
CREATE MATERIALIZED VIEW mv_admin_boundaries_lines_z3_5 AS
SELECT 
    type,
    admin_level,
    member,
    ST_SimplifyPreserveTopology(geometry, 1000) AS geometry,
    group_id,
    start_decdate,
    end_decdate,
    start_date,
    end_date
FROM mv_admin_boundaries_relations_ways
WHERE admin_level IN (1,2,3,4)
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z3_5_idx 
ON mv_admin_boundaries_lines_z3_5 (admin_level, member, group_id);

CREATE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z3_5_geometry_idx 
ON mv_admin_boundaries_lines_z3_5 USING GIST (geometry);

-- ==========================================
-- MViews for admin lines zoom 6-7
-- ==========================================
DROP MATERIALIZED VIEW IF EXISTS mv_admin_boundaries_lines_z6_7 CASCADE;
CREATE MATERIALIZED VIEW mv_admin_boundaries_lines_z6_7 AS
SELECT 
    type,
    admin_level,
    member,
    ST_SimplifyPreserveTopology(geometry, 200) AS geometry,
    group_id,
    start_decdate,
    end_decdate,
    start_date,
    end_date
FROM mv_admin_boundaries_relations_ways
WHERE admin_level IN (1,2,3,4,5,6)
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z6_7_idx 
ON mv_admin_boundaries_lines_z6_7 (admin_level, member, group_id);

CREATE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z6_7_geometry_idx 
ON mv_admin_boundaries_lines_z6_7 USING GIST (geometry);

-- ==========================================
-- MViews for admin lines zoom 8-9
-- ==========================================
DROP MATERIALIZED VIEW IF EXISTS mv_admin_boundaries_lines_z8_9 CASCADE;
CREATE MATERIALIZED VIEW mv_admin_boundaries_lines_z8_9 AS
SELECT 
    type,
    admin_level,
    member,
    ST_SimplifyPreserveTopology(geometry, 100) AS geometry,
    group_id,
    start_decdate,
    end_decdate,
    start_date,
    end_date
FROM mv_admin_boundaries_relations_ways
WHERE admin_level IN (1,2,3,4,5,6,7,8,9)
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z8_9_idx 
ON mv_admin_boundaries_lines_z8_9 (admin_level, member, group_id);

CREATE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z8_9_geometry_idx 
ON mv_admin_boundaries_lines_z8_9 USING GIST (geometry);

-- ==========================================
-- MViews for admin lines zoom 10-12
-- ==========================================
DROP MATERIALIZED VIEW IF EXISTS mv_admin_boundaries_lines_z10_12 CASCADE;
CREATE MATERIALIZED VIEW mv_admin_boundaries_lines_z10_12 AS
SELECT 
    type,
    admin_level,
    member,
    ST_SimplifyPreserveTopology(geometry, 20) AS geometry,
    group_id,
    start_decdate,
    end_decdate,
    start_date,
    end_date
FROM mv_admin_boundaries_relations_ways
WHERE admin_level IN (1,2,3,4,5,6,7,8,9,10)
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z10_12_idx 
ON mv_admin_boundaries_lines_z10_12 (admin_level, member, group_id);

CREATE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z10_12_geometry_idx 
ON mv_admin_boundaries_lines_z10_12 USING GIST (geometry);

-- ==========================================
-- MViews for admin lines zoom 13-15
-- ==========================================
DROP MATERIALIZED VIEW IF EXISTS mv_admin_boundaries_lines_z13_15 CASCADE;
CREATE MATERIALIZED VIEW mv_admin_boundaries_lines_z13_15 AS
SELECT 
    type,
    admin_level,
    member,
    ST_SimplifyPreserveTopology(geometry, 5) AS geometry,
    group_id,
    start_decdate,
    end_decdate,
    start_date,
    end_date
FROM mv_admin_boundaries_relations_ways
WHERE admin_level IN (1,2,3,4,5,6,7,8,9,10)
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z13_15_idx 
ON mv_admin_boundaries_lines_z13_15 (admin_level, member, group_id);

CREATE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z13_15_geometry_idx 
ON mv_admin_boundaries_lines_z13_15 USING GIST (geometry);

-- ==========================================
-- MViews for admin lines zoom 16-20
-- ==========================================
DROP MATERIALIZED VIEW IF EXISTS mv_admin_boundaries_lines_z16_20 CASCADE;
CREATE MATERIALIZED VIEW mv_admin_boundaries_lines_z16_20 AS
SELECT 
    type,
    admin_level,
    member,
    ST_SimplifyPreserveTopology(geometry, 1) AS geometry,
    group_id,
    start_decdate,
    end_decdate,
    start_date,
    end_date
FROM mv_admin_boundaries_relations_ways
WHERE admin_level IN (1,2,3,4,5,6,7,8,9,10)
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z16_20_idx 
ON mv_admin_boundaries_lines_z16_20 (admin_level, member, group_id);

CREATE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z16_20_geometry_idx 
ON mv_admin_boundaries_lines_z16_20 USING GIST (geometry);
