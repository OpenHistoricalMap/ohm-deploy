-- This script creates materialized views for land polygons.
-- ==========================
-- MATERIALIZED VIEW FOR LAND_Z0_2
-- ==========================
DROP MATERIALIZED VIEW IF EXISTS mview_land_z0_2 CASCADE;
CREATE MATERIALIZED VIEW mview_land_z0_2 AS
SELECT 
    ST_Simplify(wkb_geometry, 500) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 500) IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_mview_land_z0_2_geom ON mview_land_z0_2 USING GIST (geometry);
CREATE INDEX IF NOT EXISTS idx_mview_land_z0_2_ogc_fid ON mview_land_z0_2 (ogc_fid);


-- ==========================
-- MATERIALIZED VIEW FOR LAND_Z3_5
-- ==========================
DROP MATERIALIZED VIEW IF EXISTS mview_land_z3_5 CASCADE;
CREATE MATERIALIZED VIEW mview_land_z3_5 AS
SELECT 
    ST_Simplify(wkb_geometry, 200) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 200) IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_mview_land_z3_5_geom ON mview_land_z3_5 USING GIST (geometry);
CREATE INDEX IF NOT EXISTS idx_mview_land_z3_5_ogc_fid ON mview_land_z3_5 (ogc_fid);


-- ==========================
-- MATERIALIZED VIEW FOR LAND_Z6_7
-- ==========================
DROP MATERIALIZED VIEW IF EXISTS mview_land_z6_7 CASCADE;
CREATE MATERIALIZED VIEW mview_land_z6_7 AS
SELECT 
    ST_Simplify(wkb_geometry, 70) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 70) IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_mview_land_z6_7_geom ON mview_land_z6_7 USING GIST (geometry);
CREATE INDEX IF NOT EXISTS idx_mview_land_z6_7_ogc_fid ON mview_land_z6_7 (ogc_fid);


-- ==========================
-- MATERIALIZED VIEW FOR LAND_Z8_9
-- ==========================
DROP MATERIALIZED VIEW IF EXISTS mview_land_z8_9 CASCADE;
CREATE MATERIALIZED VIEW mview_land_z8_9 AS
SELECT 
    ST_Simplify(wkb_geometry, 30) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 30) IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_mview_land_z8_9_geom ON mview_land_z8_9 USING GIST (geometry);
CREATE INDEX IF NOT EXISTS idx_mview_land_z8_9_ogc_fid ON mview_land_z8_9 (ogc_fid);


-- ==========================
-- MATERIALIZED VIEW FOR LAND_Z10_12
-- ==========================
DROP MATERIALIZED VIEW IF EXISTS mview_land_z10_12 CASCADE;
CREATE MATERIALIZED VIEW mview_land_z10_12 AS
SELECT 
    ST_Simplify(wkb_geometry, 10) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 10) IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_mview_land_z10_12_geom ON mview_land_z10_12 USING GIST (geometry);
CREATE INDEX IF NOT EXISTS idx_mview_land_z10_12_ogc_fid ON mview_land_z10_12 (ogc_fid);


-- ==========================
-- MATERIALIZED VIEW FOR LAND_Z13_15
-- ==========================
DROP MATERIALIZED VIEW IF EXISTS mview_land_z13_15 CASCADE;
CREATE MATERIALIZED VIEW mview_land_z13_15 AS
SELECT 
    ST_Simplify(wkb_geometry, 5) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 5) IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_mview_land_z13_15_geom ON mview_land_z13_15 USING GIST (geometry);
CREATE INDEX IF NOT EXISTS idx_mview_land_z13_15_ogc_fid ON mview_land_z13_15 (ogc_fid);


-- ==========================
-- MATERIALIZED VIEW FOR LAND_Z16_20
-- ==========================
DROP MATERIALIZED VIEW IF EXISTS mview_land_z16_20 CASCADE;
CREATE MATERIALIZED VIEW mview_land_z16_20 AS
SELECT 
    ST_Simplify(wkb_geometry, 1) AS geometry, 
    ogc_fid
FROM land_polygons
WHERE wkb_geometry IS NOT NULL
  AND ST_Simplify(wkb_geometry, 1) IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_mview_land_z16_20_geom ON mview_land_z16_20 USING GIST (geometry);
CREATE INDEX IF NOT EXISTS idx_mview_land_z16_20_ogc_fid ON mview_land_z16_20 (ogc_fid);
