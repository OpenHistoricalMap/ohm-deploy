-- Drop the materialized view if it exists
DROP MATERIALIZED VIEW IF EXISTS mview_ne_lakes CASCADE;

-- Create the materialized view with a unique serial ID
CREATE MATERIALIZED VIEW mview_ne_lakes AS
SELECT 
    ROW_NUMBER() OVER () AS id,  -- Generates a unique sequential ID
    name,
    ST_Simplify(wkb_geometry, 100) AS wkb_geometry,
    'ne_10m_lakes' AS source_table
FROM ne_10m_lakes
WHERE ST_Simplify(wkb_geometry, 100) IS NOT NULL

UNION ALL
SELECT 
    ROW_NUMBER() OVER () + (SELECT COUNT(*) FROM ne_10m_lakes WHERE wkb_geometry IS NOT NULL) AS id,  
    name,
    ST_Simplify(wkb_geometry, 100) AS wkb_geometry,
    'ne_10m_lakes_europe' AS source_table
FROM ne_10m_lakes_europe
WHERE ST_Simplify(wkb_geometry, 100) IS NOT NULL

UNION ALL
SELECT 
    ROW_NUMBER() OVER () 
    + (SELECT COUNT(*) FROM ne_10m_lakes WHERE wkb_geometry IS NOT NULL) 
    + (SELECT COUNT(*) FROM ne_10m_lakes_europe WHERE wkb_geometry IS NOT NULL) AS id,  
    name,
    ST_Simplify(wkb_geometry, 100) AS wkb_geometry,
    'ne_10m_lakes_north_america' AS source_table
FROM ne_10m_lakes_north_america
WHERE ST_Simplify(wkb_geometry, 100) IS NOT NULL;

-- Create spatial and ID indexes
CREATE INDEX idx_mview_ne_lakes_geom ON mview_ne_lakes USING GIST (wkb_geometry);
CREATE INDEX idx_mview_ne_lakes_id ON mview_ne_lakes (id);