-- This script creates a materialized view for lakes in the Natural Earth dataset, merging data from multiple source tables.
DROP MATERIALIZED VIEW IF EXISTS mview_ne_lakes CASCADE;

-- Create a new materialized view
CREATE MATERIALIZED VIEW mview_ne_lakes AS
SELECT 
    'ne_10m_lakes_' || CAST(ogc_fid AS TEXT) AS ogc_fid,
    name,
    wkb_geometry,
    'ne_10m_lakes' AS source_table
FROM ne_10m_lakes

UNION ALL
SELECT 
    'ne_10m_lakes_europe_' || CAST(ogc_fid AS TEXT) AS ogc_fid,
    name,
    wkb_geometry,
    'ne_10m_lakes_europe' AS source_table
FROM ne_10m_lakes_europe

UNION ALL
SELECT 
    'ne_10m_lakes_north_america_' || CAST(ogc_fid AS TEXT) AS ogc_fid,
    name,
    wkb_geometry,
    'ne_10m_lakes_north_america' AS source_table
FROM ne_10m_lakes_north_america;

CREATE INDEX idx_mview_ne_lakes_geom ON mview_ne_lakes USING GIST (wkb_geometry);
CREATE INDEX idx_mview_ne_lakes_ogc_fid ON mview_ne_lakes (ogc_fid);
