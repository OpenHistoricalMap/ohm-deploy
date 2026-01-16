/**
layers: admin_boundaries_lines
tegola_config: config/providers/admin_boundaries_lines.toml
filters_per_zoom_level:
- z16-20: mv_admin_boundaries_lines_z16_20 | tolerance=1m | filter=admin_level IN (1,2,3,4,5,6,7,8,9,10,11) | source=mv_admin_boundaries_relations_ways
- z13-15: mv_admin_boundaries_lines_z13_15 | tolerance=5m | filter=admin_level IN (1,2,3,4,5,6,7,8,9,10) | source=mv_admin_boundaries_lines_z16_20
- z10-12: mv_admin_boundaries_lines_z10_12 | tolerance=20m | filter=(inherited from z13-15) | source=mv_admin_boundaries_lines_z13_15
- z8-9:   mv_admin_boundaries_lines_z8_9   | tolerance=100m | filter=admin_level IN (1,2,3,4,5,6,7,8,9) | source=mv_admin_boundaries_lines_z10_12
- z6-7:   mv_admin_boundaries_lines_z6_7   | tolerance=200m | filter=admin_level IN (1,2,3,4,5,6) | source=mv_admin_boundaries_lines_z8_9
- z3-5:   mv_admin_boundaries_lines_z3_5   | tolerance=1000m | filter=admin_level IN (1,2,3,4) | source=mv_admin_boundaries_lines_z6_7
- z0-2:   mv_admin_boundaries_lines_z0_2   | tolerance=5000m | filter=admin_level IN (1,2) | source=mv_admin_boundaries_lines_z3_5

## description:
OpenhistoricalMap admin boundaries lines, contains administrative boundary lines (country borders, state/province boundaries, etc.) with temporal information

## details:
- Combines data from relations (osm_relation_members_boundaries) and ways (osm_admin_lines)
- Merges adjacent lines with overlapping or continuous date ranges (start_decdate/end_decdate) grouped by admin_level, member, and type
- Uses admin_level to filter boundaries by administrative level (higher levels shown at lower zooms)
**/


-- ============================================================================
--STEP 1: Add New Columns in osm_relation_members_boundaries and osm_admin_lines
-- ============================================================================
SELECT log_notice('STEP 1: Adding new columns in osm_relation_members_boundaries and osm_admin_lines table');

-- osm_relation_members_boundaries
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'osm_relation_members_boundaries' 
    AND column_name = 'start_decdate'
  ) THEN
    ALTER TABLE osm_relation_members_boundaries ADD COLUMN start_decdate DOUBLE PRECISION;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'osm_relation_members_boundaries' 
    AND column_name = 'end_decdate'
  ) THEN
    ALTER TABLE osm_relation_members_boundaries ADD COLUMN end_decdate DOUBLE PRECISION;
  END IF;
END $$;

-- osm_admin_lines
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'osm_admin_lines' 
    AND column_name = 'start_decdate'
  ) THEN
    ALTER TABLE osm_admin_lines ADD COLUMN start_decdate DOUBLE PRECISION;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'osm_admin_lines' 
    AND column_name = 'end_decdate'
  ) THEN
    ALTER TABLE osm_admin_lines ADD COLUMN end_decdate DOUBLE PRECISION;
  END IF;
END $$;


-- ============================================================================
-- STEP 2: Create the Trigger, which will call the function above
-- ============================================================================
SELECT log_notice('STEP 2: Create trigger to convert date to decimal for new/updated objects in osm_relation_members_boundaries and osm_admin_lines table');

-- osm_relation_members_boundaries trigger
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'trigger_decimal_dates_osm_relation_members_boundaries'
  ) THEN
    CREATE TRIGGER trigger_decimal_dates_osm_relation_members_boundaries 
    BEFORE INSERT OR UPDATE 
    ON osm_relation_members_boundaries
    FOR EACH ROW
    EXECUTE FUNCTION convert_dates_to_decimal();
  END IF;
END $$;

-- osm_admin_lines trigger
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'trigger_decimal_dates_osm_admin_lines'
  ) THEN
    CREATE TRIGGER trigger_decimal_dates_osm_admin_lines
    BEFORE INSERT OR UPDATE 
    ON osm_admin_lines
    FOR EACH ROW
    EXECUTE FUNCTION convert_dates_to_decimal();
  END IF;
END $$;

-- ============================================================================
-- STEP 3: Backfill Existing Data, Set timeout to 40 minutes (2400000 milliseconds) for the current session, this takes quite a while, sincecurrnelty thrre are ~5 million rows in the table
-- ============================================================================
SELECT log_notice('STEP 3: Backfill existing data for osm_relation_members_boundaries table');
SET statement_timeout = 2400000;
UPDATE osm_relation_members_boundaries
SET start_decdate = isodatetodecimaldate(pad_date(start_date::TEXT, 'start')::TEXT, FALSE),
    end_decdate = isodatetodecimaldate(pad_date(end_date::TEXT, 'end')::TEXT, FALSE)
WHERE ST_GeometryType(geometry) = 'ST_LineString';


SELECT log_notice('STEP 3: Backfill existing data for osm_admin_lines table');
SET statement_timeout = 2400000;
UPDATE osm_admin_lines
SET start_decdate = isodatetodecimaldate(pad_date(start_date::TEXT, 'start')::TEXT, FALSE),
    end_decdate = isodatetodecimaldate(pad_date(end_date::TEXT, 'end')::TEXT, FALSE)
WHERE ST_GeometryType(geometry) = 'ST_LineString';


-- ============================================================================
-- STEP 4: Create a materialized view that merges lines based on start_decdate and end_decdate, admin_level, member and type
-- ============================================================================
SELECT log_notice('STEP 4: Create a materialized view that merges lines based on start_decdate and end_decdate using osm_relation_members_boundaries table');

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
SELECT log_notice('STEP 5: Create a materialized view that combines the data from mv_relation_members_boundaries and osm_admin_lines');

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
SELECT log_notice('STEP 6: Create a materialized view for zoom levels');

-- ==========================================
-- MViews for admin lines zoom 16-20
-- ==========================================
DROP MATERIALIZED VIEW IF EXISTS mv_admin_boundaries_lines_z16_20 CASCADE;
CREATE MATERIALIZED VIEW mv_admin_boundaries_lines_z16_20 AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY admin_level, member, group_id) AS id,
    type,
    admin_level,
    member as osm_id,
    ST_SimplifyPreserveTopology(geometry, 1) AS geometry,
    group_id,
    start_decdate,
    end_decdate,
    start_date,
    end_date
FROM mv_admin_boundaries_relations_ways
WHERE admin_level IN (1,2,3,4,5,6,7,8,9,10,11)
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z16_20_id_idx 
ON mv_admin_boundaries_lines_z16_20 (id);

CREATE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z16_20_admin_level_idx 
ON mv_admin_boundaries_lines_z16_20 (admin_level);

CREATE INDEX IF NOT EXISTS mv_admin_boundaries_lines_z16_20_geometry_idx 
ON mv_admin_boundaries_lines_z16_20 USING GIST (geometry);

SELECT create_mview_line_from_mview('mv_admin_boundaries_lines_z16_20', 'mv_admin_boundaries_lines_z13_15', 5, 'admin_level IN (1,2,3,4,5,6,7,8,9,10)');
SELECT create_mview_line_from_mview('mv_admin_boundaries_lines_z13_15', 'mv_admin_boundaries_lines_z10_12', 20, NULL);
SELECT create_mview_line_from_mview('mv_admin_boundaries_lines_z10_12', 'mv_admin_boundaries_lines_z8_9', 100, 'admin_level IN (1,2,3,4,5,6,7,8,9)');
SELECT create_mview_line_from_mview('mv_admin_boundaries_lines_z8_9', 'mv_admin_boundaries_lines_z6_7', 200, 'admin_level IN (1,2,3,4,5,6)');
SELECT create_mview_line_from_mview('mv_admin_boundaries_lines_z6_7', 'mv_admin_boundaries_lines_z3_5', 1000, 'admin_level IN (1,2,3,4)');
SELECT create_mview_line_from_mview('mv_admin_boundaries_lines_z3_5', 'mv_admin_boundaries_lines_z0_2', 5000, 'admin_level IN (1,2)');

-- Refresh lines views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_relation_members_boundaries;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_relations_ways;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_lines_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_lines_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_lines_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_lines_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_lines_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_lines_z3_5;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_lines_z0_2;
