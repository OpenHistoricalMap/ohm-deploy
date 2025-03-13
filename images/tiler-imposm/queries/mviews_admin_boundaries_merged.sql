-- This script creates materialized views for admin boundaries (lines) merged by admin_level, member, and type.
-- This script should be run right after importing the OSM data. It will create materialized views for each zoom level range and refresh them only when needed.

-- STEP 1: Add New Columns in osm_relation_members_boundaries table
ALTER TABLE osm_relation_members_boundaries 
ADD COLUMN start_decdate DOUBLE PRECISION,
ADD COLUMN end_decdate DOUBLE PRECISION;

-- STEP 2: Create a function that will be triggered on INSERT and UPDATE to automatically populate start_decdate and end_decdate based on start_date and end_date
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

-- STEP 3: Create the Trigger, which will call the function above
CREATE TRIGGER trigger_update_decimal_dates
BEFORE INSERT OR UPDATE 
ON osm_relation_members_boundaries
FOR EACH ROW
EXECUTE FUNCTION decimal_dates_members_boundaries();


-- STEP 4: Backfill Existing Data, Set timeout to 40 minutes (2400000 milliseconds) for the current session, this takes quite a while, sincecurrnelty thrre are ~5 million rows in the table
SET statement_timeout = 2400000;
UPDATE osm_relation_members_boundaries
SET start_decdate = isodatetodecimaldate(pad_date(start_date::TEXT, 'start')::TEXT, FALSE),
    end_decdate = isodatetodecimaldate(pad_date(end_date::TEXT, 'end')::TEXT, FALSE)
WHERE ST_GeometryType(geometry) = 'ST_LineString';


-- STEP 5: Create the function to merge lines based on admin_level, member, and type
-- This function will create a materialized view that merges lines based on start_decdate and end_decdate, admin_level, member and type
-- The function will also simplify the geometries based on the simplification factor provided
-- The function will create a unique index on admin_level, member, type, and group_id to improve concurrent refresh performance
-- The function will create a spatial index on the geometry column
-- The function will return the merged geometries, the count of rows merged, the minimum and maximum start and end decimal dates, and the converted ISO dates for the decimal dates
-- The function will also return the first non-null value found in the group for maritime, dispute, indefinite, and indeterminate attributes
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
    -- Drop the materialized view if it already exists
    sql := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
    EXECUTE sql;

    -- Construct the query for the materialized view
    sql := format(
        'CREATE MATERIALIZED VIEW %I AS
        WITH ordered AS (
          SELECT
            type,
            admin_level,
            member,
            ST_SimplifyPreserveTopology(geometry, %L) AS geometry, 
            start_decdate,  
            end_decdate,    
            -- Extra attributes from ways
            (me_tags::JSONB)->>''maritime'' AS maritime,
            (me_tags::JSONB)->>''dispute'' AS dispute,
            (me_tags::JSONB)->>''indefinite'' AS indefinite,
            (me_tags::JSONB)->>''indeterminate'' AS indeterminate,
            LAG(end_decdate) OVER (
              PARTITION BY admin_level, member, type  
              ORDER BY start_decdate NULLS FIRST
            ) AS prev_end
          FROM osm_relation_members_boundaries
          WHERE ST_GeometryType(geometry) = ''ST_LineString''
          AND geometry IS NOT NULL 
          AND %s
        ),

        flagged AS (
          SELECT
            type,
            admin_level,
            member,
            geometry,
            start_decdate,  
            end_decdate,
            maritime,
            dispute,
            indefinite,
            indeterminate,   
            CASE 
              WHEN prev_end IS NULL THEN 0               
              WHEN start_decdate IS NULL THEN 0         
              WHEN start_decdate <= prev_end + 1 THEN 0 -- No gap, Note: +1 in 1 year in decimal date to overlap the dates, so that they are considered as continuous, this can be evaluete in decimal, for now we are using 1.
              ELSE 1
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
            maritime,
            dispute,
            indefinite,
            indeterminate, 
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
          ) AS max_end_date_iso,

          -- Return the first non-null value found in the group
          COALESCE(
            (ARRAY_AGG(maritime ORDER BY maritime NULLS LAST))[1], 
            NULL
          ) AS maritime,

          COALESCE(
            (ARRAY_AGG(dispute ORDER BY dispute NULLS LAST))[1], 
            NULL
          ) AS dispute,

          COALESCE(
            (ARRAY_AGG(indefinite ORDER BY indefinite NULLS LAST))[1], 
            NULL
          ) AS indefinite,

          COALESCE(
            (ARRAY_AGG(indeterminate ORDER BY indeterminate NULLS LAST))[1], 
            NULL
          ) AS indeterminate     
        FROM grouped
        GROUP BY 
          type, admin_level, member, group_id
        WITH DATA;', 
        view_name, simplification, filter_condition
    );

    -- Execute the query to create the materialized view
    EXECUTE sql;

    -- Create a unique index to improve concurrent refresh performance
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

    RAISE NOTICE 'Materialized view % created successfully', view_name;
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
