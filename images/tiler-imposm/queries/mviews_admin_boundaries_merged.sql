-- This script creates materialized views for admin boundaries (lines) merged by admin_level, member, and type.
-- The script also creates a function to backfill start_decdate and end_decdate columns in osm_relation_members_boundaries table.
-- Add New Columns in osm_relation_members_boundaries table
ALTER TABLE osm_relation_members_boundaries 
ADD COLUMN start_decdate DOUBLE PRECISION,
ADD COLUMN end_decdate DOUBLE PRECISION;

-- This function will be triggered on INSERT and UPDATE to automatically populate start_decdate and end_decdate based on start_date and end_date
CREATE OR REPLACE FUNCTION decimal_dates_members_boundaries ()
RETURNS TRIGGER AS
$$
BEGIN
    NEW.start_decdate := isodatetodecimaldate(pad_date(NEW.start_date::TEXT, 'start')::TEXT, FALSE);
    NEW.end_decdate := isodatetodecimaldate(pad_date(NEW.end_date::TEXT, 'end')::TEXT, FALSE);
    RETURN NEW;
END;
$$
LANGUAGE plpgsql;

-- Create the Trigger
CREATE TRIGGER trigger_update_decimal_dates
BEFORE INSERT OR UPDATE 
ON osm_relation_members_boundaries
FOR EACH ROW
EXECUTE FUNCTION decimal_dates_members_boundaries();


-- Backfill Existing Data, Set timeout to 20 minutes (1200000 milliseconds) for the current session
SET statement_timeout = 1200000;
UPDATE osm_relation_members_boundaries
SET start_decdate = isodatetodecimaldate(pad_date(start_date::TEXT, 'start')::TEXT, FALSE),
    end_decdate = isodatetodecimaldate(pad_date(end_date::TEXT, 'end')::TEXT, FALSE)
WHERE ST_GeometryType(geometry) = 'ST_LineString';


-- Create Materialized Views for Admin Boundaries (Lines)
CREATE OR REPLACE FUNCTION create_merge_lines_boundaries(
    view_name TEXT, 
    simplification FLOAT, 
    filter_condition TEXT
)
RETURNS VOID AS
$$
DECLARE
    sql TEXT;
BEGIN
    -- Drop the materialized view if it exists
    sql := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
    EXECUTE sql;

    -- Construct the SQL query dynamically
    sql := format(
        'CREATE MATERIALIZED VIEW %I AS
        WITH ordered AS (
          SELECT
            admin_level,
            member,
            type,  
            ST_Simplify(geometry, %L) AS geometry, 
            start_decdate,  
            end_decdate,    
            LAG(end_decdate) OVER (
              PARTITION BY admin_level, member, type  
              ORDER BY start_decdate
            ) AS prev_end
          FROM osm_relation_members_boundaries
          WHERE ST_GeometryType(geometry) = ''ST_LineString''
          AND geometry IS NOT NULL 
          AND ST_Simplify(geometry, %L) IS NOT NULL 
          AND %s 
        ),

        flagged AS (
          SELECT
            admin_level,
            member,
            type,  
            geometry,
            start_decdate,  
            end_decdate,    
            CASE 
              WHEN prev_end IS NULL THEN 0               
              WHEN start_decdate <= prev_end + 1 THEN 0  
              ELSE 1
            END AS gap_flag
          FROM ordered
        ),

        grouped AS (
          SELECT
            admin_level,
            member,
            type,  
            geometry,
            start_decdate,  
            end_decdate,    
            SUM(gap_flag) OVER (
              PARTITION BY admin_level, member, type  
              ORDER BY start_decdate
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS group_id
          FROM flagged
        )

        SELECT
          admin_level,
          member,
          type,  
          group_id,
          COUNT(*) AS group_count,         
          (array_agg(geometry))[1] AS geometry,
          MIN(start_decdate) AS min_start_date,    
          MAX(end_decdate)   AS max_end_date       
        FROM grouped
        GROUP BY 
          admin_level,
          member,
          type,   
          group_id
        WITH DATA;', 
        view_name, simplification, simplification, filter_condition);

    -- Execute the SQL query
    EXECUTE sql;

    -- Create unique index for concurrent refresh
    sql := format(
        'CREATE UNIQUE INDEX IF NOT EXISTS %I_idx 
        ON %I (admin_level, member, type, group_id);',
        view_name, view_name);
    EXECUTE sql;

    -- Create a spatial index on the geometry column
    sql := format(
        'CREATE INDEX IF NOT EXISTS %I_geometry_idx 
        ON %I USING GIST (geometry);',
        view_name, view_name);
    EXECUTE sql;
END;
$$
LANGUAGE plpgsql;

SELECT create_merge_lines_boundaries('mview_admin_boundaries_lines_merged_z0_2', 5000, 'admin_level IN (1,2)');
SELECT create_merge_lines_boundaries('mview_admin_boundaries_lines_merged_z3_5', 1000, 'admin_level IN (1,2,3,4)');
SELECT create_merge_lines_boundaries('mview_admin_boundaries_lines_merged_z6_7', 200, 'admin_level IN (1,2,3,4,5,6)');
SELECT create_merge_lines_boundaries('mview_admin_boundaries_lines_merged_z8_9', 100, 'admin_level IN (1,2,3,4,5,6,7,8,9)');
SELECT create_merge_lines_boundaries('mview_admin_boundaries_lines_merged_z10_12', 20, 'admin_level IN (1,2,3,4,5,6,7,8,9,10)');
SELECT create_merge_lines_boundaries('mview_admin_boundaries_lines_merged_z13_15', 5, 'admin_level IN (1,2,3,4,5,6,7,8,9,10)');
SELECT create_merge_lines_boundaries('mview_admin_boundaries_lines_merged_z16_20', 1, 'admin_level IN (1,2,3,4,5,6,7,8,9,10)');
