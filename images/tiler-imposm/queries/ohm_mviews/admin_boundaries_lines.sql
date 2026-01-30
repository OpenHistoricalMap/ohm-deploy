-- This script creates materialized views for admin boundaries (lines) combined from tables osm_admin_relation_members and osm_admin_lines

-- ============================================================================
-- STEP 1: Add New Columns in osm_admin_relation_members and osm_admin_lines
-- ============================================================================
SELECT log_notice('STEP 1: Adding new columns in osm_admin_relation_members and osm_admin_lines table');

-- osm_admin_relation_members
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'osm_admin_relation_members' 
    AND column_name = 'start_decdate'
  ) THEN
    ALTER TABLE osm_admin_relation_members ADD COLUMN start_decdate DOUBLE PRECISION;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'osm_admin_relation_members' 
    AND column_name = 'end_decdate'
  ) THEN
    ALTER TABLE osm_admin_relation_members ADD COLUMN end_decdate DOUBLE PRECISION;
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
-- STEP 2: Backfill Existing Data using temp table + disabled indexes
-- ============================================================================

-- Configuracion temporal para mejor rendimiento
SET LOCAL work_mem = '512MB';
SET LOCAL maintenance_work_mem = '1GB';

-- ============================================
-- 2.1 Backfill osm_admin_relation_members
-- ============================================
SELECT log_notice('STEP 2.1: Backfill existing data for osm_admin_relation_members table');

-- Guardar definiciones de indices antes de dropearlos
CREATE TEMP TABLE saved_indexes_relation_members AS
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'osm_admin_relation_members'
  AND indexname NOT LIKE '%_pkey';

-- Dropear indices temporalmente (excepto PK)
DO $$
DECLARE
  idx RECORD;
BEGIN
  FOR idx IN
    SELECT indexname FROM pg_indexes
    WHERE tablename = 'osm_admin_relation_members'
      AND indexname NOT LIKE '%_pkey'
  LOOP
    EXECUTE 'DROP INDEX IF EXISTS ' || idx.indexname;
    RAISE NOTICE 'Dropped index: %', idx.indexname;
  END LOOP;
END $$;

-- Crear tabla temporal con valores pre-calculados
SELECT log_notice('STEP 2.1: Creating temp table with pre-calculated values for osm_admin_relation_members');
CREATE TEMP TABLE temp_admin_relation_members_backfill AS
SELECT
  ctid AS row_ctid,
  isodatetodecimaldate(pad_date(start_date::TEXT, 'start')::TEXT, FALSE) AS start_decdate,
  isodatetodecimaldate(pad_date(end_date::TEXT, 'end')::TEXT, FALSE) AS end_decdate
FROM osm_admin_relation_members
WHERE ST_GeometryType(geometry) = 'ST_LineString'
  AND type = 'administrative'
  AND (start_decdate IS NULL OR end_decdate IS NULL);

CREATE INDEX ON temp_admin_relation_members_backfill(row_ctid);

-- UPDATE masivo con JOIN
SELECT log_notice('STEP 2.1: Updating osm_admin_relation_members with pre-calculated values');
UPDATE osm_admin_relation_members t
SET start_decdate = tmp.start_decdate,
    end_decdate = tmp.end_decdate
FROM temp_admin_relation_members_backfill tmp
WHERE t.ctid = tmp.row_ctid;

DROP TABLE temp_admin_relation_members_backfill;

-- Recrear todos los indices guardados
SELECT log_notice('STEP 2.1: Recreating indexes for osm_admin_relation_members');
DO $$
DECLARE
  idx RECORD;
BEGIN
  FOR idx IN SELECT indexname, indexdef FROM saved_indexes_relation_members
  LOOP
    EXECUTE idx.indexdef;
    RAISE NOTICE 'Recreated index: %', idx.indexname;
  END LOOP;
END $$;

DROP TABLE saved_indexes_relation_members;
SELECT log_notice('STEP 2.1: osm_admin_relation_members backfill complete');


-- ============================================
-- 2.2 Backfill osm_admin_lines
-- ============================================
SELECT log_notice('STEP 2.2: Backfill existing data for osm_admin_lines table');

-- Guardar definiciones de indices antes de dropearlos
CREATE TEMP TABLE saved_indexes_admin_lines AS
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'osm_admin_lines'
  AND indexname NOT LIKE '%_pkey';

-- Dropear indices temporalmente (excepto PK)
DO $$
DECLARE
  idx RECORD;
BEGIN
  FOR idx IN
    SELECT indexname FROM pg_indexes
    WHERE tablename = 'osm_admin_lines'
      AND indexname NOT LIKE '%_pkey'
  LOOP
    EXECUTE 'DROP INDEX IF EXISTS ' || idx.indexname;
    RAISE NOTICE 'Dropped index: %', idx.indexname;
  END LOOP;
END $$;

-- Crear tabla temporal con valores pre-calculados
SELECT log_notice('STEP 2.2: Creating temp table with pre-calculated values for osm_admin_lines');
CREATE TEMP TABLE temp_admin_lines_backfill AS
SELECT
  ctid AS row_ctid,
  isodatetodecimaldate(pad_date(start_date::TEXT, 'start')::TEXT, FALSE) AS start_decdate,
  isodatetodecimaldate(pad_date(end_date::TEXT, 'end')::TEXT, FALSE) AS end_decdate
FROM osm_admin_lines
WHERE ST_GeometryType(geometry) = 'ST_LineString'
  AND type = 'administrative'
  AND (start_decdate IS NULL OR end_decdate IS NULL);

CREATE INDEX ON temp_admin_lines_backfill(row_ctid);

-- UPDATE masivo con JOIN
SELECT log_notice('STEP 2.2: Updating osm_admin_lines with pre-calculated values');
UPDATE osm_admin_lines t
SET start_decdate = tmp.start_decdate,
    end_decdate = tmp.end_decdate
FROM temp_admin_lines_backfill tmp
WHERE t.ctid = tmp.row_ctid;

DROP TABLE temp_admin_lines_backfill;

-- Recrear todos los indices guardados
SELECT log_notice('STEP 2.2: Recreating indexes for osm_admin_lines');
DO $$
DECLARE
  idx RECORD;
BEGIN
  FOR idx IN SELECT indexname, indexdef FROM saved_indexes_admin_lines
  LOOP
    EXECUTE idx.indexdef;
    RAISE NOTICE 'Recreated index: %', idx.indexname;
  END LOOP;
END $$;

DROP TABLE saved_indexes_admin_lines;
SELECT log_notice('STEP 2.2: osm_admin_lines backfill complete');


-- ============================================================================
-- STEP 2.3: Create additional indexes for query performance (after backfill)
-- ============================================================================
SELECT log_notice('STEP 2.3: Creating additional indexes for query performance');

CREATE INDEX IF NOT EXISTS osm_admin_relation_members_type_idx ON osm_admin_relation_members (type);
CREATE INDEX IF NOT EXISTS osm_admin_lines_type_idx ON osm_admin_lines (type);
CREATE INDEX IF NOT EXISTS osm_relation_members_role_idx ON osm_admin_relation_members (role);

CREATE INDEX IF NOT EXISTS osm_admin_relation_members_linestring_idx
ON osm_admin_relation_members (admin_level, member, type)
WHERE ST_GeometryType(geometry) = 'ST_LineString';

CREATE INDEX IF NOT EXISTS osm_admin_lines_linestring_idx
ON osm_admin_lines (type)
WHERE ST_GeometryType(geometry) = 'ST_LineString';

SELECT log_notice('STEP 2.3: Indexes created successfully');


-- ============================================================================
-- STEP 3: Create the Trigger, which will call the function above
-- ============================================================================
SELECT log_notice('STEP 3: Create trigger to convert date to decimal for new/updated objects in osm_admin_relation_members and osm_admin_lines table');

-- osm_admin_relation_members trigger
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'trigger_decimal_dates_osm_admin_relation_members'
  ) THEN
    CREATE TRIGGER trigger_decimal_dates_osm_admin_relation_members 
    BEFORE INSERT OR UPDATE 
    ON osm_admin_relation_members
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
-- STEP 4: Create a materialized view that merges lines based on start_decdate and end_decdate, admin_level, member and type
-- ============================================================================
SELECT log_notice('STEP 4: Create a materialized view that merges lines based on start_decdate and end_decdate using osm_admin_relation_members table');

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
  FROM osm_admin_relation_members
  WHERE ST_GeometryType(geometry) = 'ST_LineString'
    AND type = 'administrative'
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
