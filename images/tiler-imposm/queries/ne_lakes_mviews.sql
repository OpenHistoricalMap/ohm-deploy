-- This is an SQL script to merge lakes tables into materialized views.
CREATE MATERIALIZED VIEW mview_ne_lakes AS
SELECT 
    'ne_10m_lakes_' || ogc_fid AS ogc_fid,
    name,
    wkb_geometry,
    'ne_10m_lakes' AS source_table
FROM ne_10m_lakes

UNION ALL
SELECT 
    'ne_10m_lakes_europe_' || ogc_fid AS ogc_fid,
    name,
    wkb_geometry,
    'ne_10m_lakes_europe' AS source_table
FROM ne_10m_lakes_europe

UNION ALL
SELECT 
    'ne_10m_lakes_north_america_' || ogc_fid AS ogc_fid,
    name,
    wkb_geometry,
    'ne_10m_lakes_north_america' AS source_table
FROM ne_10m_lakes_north_america

UNION ALL
SELECT 
    'ne_110m_lakes_' || ogc_fid AS ogc_fid,
    name,
    wkb_geometry,
    'ne_110m_lakes' AS source_table
FROM ne_110m_lakes

UNION ALL
SELECT 
    'ne_50m_admin_1_states_provinces_lakes_' || ogc_fid AS ogc_fid,
    name,
    wkb_geometry,
    'ne_50m_admin_1_states_provinces_lakes' AS source_table
FROM ne_50m_admin_1_states_provinces_lakes

UNION ALL
SELECT 
    'ne_50m_lakes_' || ogc_fid AS ogc_fid,
    name,
    wkb_geometry,
    'ne_50m_lakes' AS source_table
FROM ne_50m_lakes;

CREATE INDEX idx_mview_ne_lakes_geom ON mview_ne_lakes USING GIST (wkb_geometry);
CREATE INDEX idx_mview_ne_lakes_ogc_fid ON mview_ne_lakes (ogc_fid);
