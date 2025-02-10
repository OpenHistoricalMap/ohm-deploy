-- This query creates materialized views for land polygons

-- Materialized View for land_0-2
CREATE MATERIALIZED VIEW mview_land_z0_2 AS
SELECT 
    ST_Simplify(wkb_geometry, 500) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 500) IS NOT NULL;

CREATE INDEX idx_mview_land_z0_2_geom ON mview_land_z0_2 USING GIST (geometry);
CREATE INDEX idx_mview_land_z0_2_ogc_fid ON mview_land_z0_2 (ogc_fid);

-- Materialized View for land_3-5
CREATE MATERIALIZED VIEW mview_land_z3_5 AS
SELECT 
    ST_Simplify(wkb_geometry, 200) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 200) IS NOT NULL;

CREATE INDEX idx_mview_land_z3_5_geom ON mview_land_z3_5 USING GIST (geometry);
CREATE INDEX idx_mview_land_z3_5_ogc_fid ON mview_land_z3_5 (ogc_fid);

-- Materialized View for land_6-7
CREATE MATERIALIZED VIEW mview_land_z6_7 AS
SELECT 
    ST_Simplify(wkb_geometry, 70) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 70) IS NOT NULL;

CREATE INDEX idx_mview_land_z6_7_geom ON mview_land_z6_7 USING GIST (geometry);
CREATE INDEX idx_mview_land_z6_7_ogc_fid ON mview_land_z6_7 (ogc_fid);

-- Materialized View for land_8-9
CREATE MATERIALIZED VIEW mview_land_z8_9 AS
SELECT 
    ST_Simplify(wkb_geometry, 30) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 30) IS NOT NULL;

CREATE INDEX idx_mview_land_z8_9_geom ON mview_land_z8_9 USING GIST (geometry);
CREATE INDEX idx_mview_land_z8_9_ogc_fid ON mview_land_z8_9 (ogc_fid);

-- Materialized View for land_10-12
CREATE MATERIALIZED VIEW mview_land_z10_12 AS
SELECT 
    ST_Simplify(wkb_geometry, 10) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 10) IS NOT NULL;

CREATE INDEX idx_mview_land_z10_12_geom ON mview_land_z10_12 USING GIST (geometry);
CREATE INDEX idx_mview_land_z10_12_ogc_fid ON mview_land_z10_12 (ogc_fid);

-- Materialized View for land_13-15
CREATE MATERIALIZED VIEW mview_land_z13_15 AS
SELECT 
    ST_Simplify(wkb_geometry, 5) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 5) IS NOT NULL;

CREATE INDEX idx_mview_land_z13_15_geom ON mview_land_z13_15 USING GIST (geometry);
CREATE INDEX idx_mview_land_z13_15_ogc_fid ON mview_land_z13_15 (ogc_fid);

-- Materialized View for land_16-20
CREATE MATERIALIZED VIEW mview_land_z16_20 AS
SELECT 
    ST_Simplify(wkb_geometry, 1) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 1) IS NOT NULL;

CREATE INDEX idx_mview_land_z16_20_geom ON mview_land_z16_20 USING GIST (geometry);
CREATE INDEX idx_mview_land_z16_20_ogc_fid ON mview_land_z16_20 (ogc_fid);
