-- ============================================================================
-- Water Areas Materialized Views for Multiple Zoom Levels
-- Creates a pyramid of materialized views for water areas, optimized for
-- ============================================================================

-- Delete existing views, in cascade
DROP MATERIALIZED VIEW IF EXISTS mv_water_areas_z16_20 CASCADE;

-- Zoom levels 16-20: Base view with full detail, no simplification
SELECT create_areas_mview('osm_water_areas','mv_water_areas_z16_20',0,0,'id, osm_id, type');

-- Zoom levels 13-15: Light simplification (5m tolerance), no area filter
SELECT create_area_mview_from_mview('mv_water_areas_z16_20','mv_water_areas_z13_15',5,0.0,NULL);

-- Zoom levels 10-12: Moderate simplification (20m tolerance), min area 100
SELECT create_area_mview_from_mview('mv_water_areas_z13_15','mv_water_areas_z10_12',20,100, 'type IN (''water'',''pond'',''basin'',''canal'',''mill_pond'',''riverbank'')');

-- Zoom levels 8-9: Higher simplification (100m tolerance), min area 10,000
SELECT create_area_mview_from_mview('mv_water_areas_z10_12','mv_water_areas_z8_9',100,10000, NULL);

-- Zoom levels 6-7: Very high simplification (200m tolerance), min area 1,000,000
SELECT create_area_mview_from_mview('mv_water_areas_z8_9','mv_water_areas_z6_7',200,1000000, NULL);

-- Zoom levels 3-5: Extreme simplification (1000m tolerance), min area 50,000,000
SELECT create_area_mview_from_mview('mv_water_areas_z6_7','mv_water_areas_z3_5',1000,50000000, NULL);

-- Zoom levels 0-2: Maximum simplification (5000m tolerance), min area 100,000,000
SELECT create_area_mview_from_mview('mv_water_areas_z3_5','mv_water_areas_z0_2',5000,100000000, 'type IN (''water'',''riverbank'')');

-- ============================================================================
-- Water Areas Centroids Materialized Views for Multiple Zoom Levels
-- ============================================================================
select create_mview_centroid_from_mview('mv_water_areas_z16_20','mv_water_areas_centroids_z16_20', 'name IS NOT NULL AND name <> ''''');
select create_mview_centroid_from_mview('mv_water_areas_z13_15','mv_water_areas_centroids_z13_15', 'name IS NOT NULL AND name <> ''''');
select create_mview_centroid_from_mview('mv_water_areas_z10_12','mv_water_areas_centroids_z10_12', 'name IS NOT NULL AND name <> ''''');
select create_mview_centroid_from_mview('mv_water_areas_z8_9','mv_water_areas_centroids_z8_9', 'name IS NOT NULL AND name <> ''''');


-- ============================================================================
-- Water lines Materialized Views for Multiple Zoom Levels
-- ============================================================================

SELECT create_lines_mview('osm_water_lines', 'mv_water_lines_z16_20', 0, 0, 'id, osm_id, type', 'type IN (''river'', ''canal'', ''cliff'', ''dam'', ''stream'', ''ditch'', ''drain'')');
SELECT create_mview_line_from_mview('mv_water_lines_z16_20', 'mv_water_lines_z13_15', 5, 'type IN (''river'', ''canal'', ''cliff'', ''dam'', ''stream'')');
SELECT create_mview_line_from_mview('mv_water_lines_z13_15', 'mv_water_lines_z10_12', 20, 'type IN (''river'', ''canal'', ''cliff'', ''dam'')');
SELECT create_mview_line_from_mview('mv_water_lines_z10_12', 'mv_water_lines_z8_9', 100, 'type IN (''river'', ''canal'')');

-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z3_5;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z0_2;

-- Refresh centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_areas_centroids_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_areas_centroids_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_areas_centroids_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_areas_centroids_z8_9;

-- Refresh lines views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_lines_z16_20
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_lines_z13_15
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_lines_z10_12
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_lines_z8_9