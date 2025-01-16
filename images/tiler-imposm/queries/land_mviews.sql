-- Materialized View for land_0-2
CREATE MATERIALIZED VIEW mview_land_0_2 AS
SELECT 
    ST_Simplify(wkb_geometry, 500) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 500) IS NOT NULL;

-- Materialized View for land_3-5
CREATE MATERIALIZED VIEW mview_land_3_5 AS
SELECT 
    ST_Simplify(wkb_geometry, 200) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 200) IS NOT NULL;

-- Materialized View for land_6-7
CREATE MATERIALIZED VIEW mview_land_6_7 AS
SELECT 
    ST_Simplify(wkb_geometry, 70) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 70) IS NOT NULL;

-- Materialized View for land_8-9
CREATE MATERIALIZED VIEW mview_land_8_9 AS
SELECT 
    ST_Simplify(wkb_geometry, 30) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 30) IS NOT NULL;

-- Materialized View for land_10-12
CREATE MATERIALIZED VIEW mview_land_10_12 AS
SELECT 
    ST_Simplify(wkb_geometry, 10) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 10) IS NOT NULL;

-- Materialized View for land_13-15
CREATE MATERIALIZED VIEW mview_land_13_15 AS
SELECT 
    ST_Simplify(wkb_geometry, 5) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 5) IS NOT NULL;

-- Materialized View for land_16-20
CREATE MATERIALIZED VIEW mview_land_16_20 AS
SELECT 
    ST_Simplify(wkb_geometry, 1) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 1) IS NOT NULL;