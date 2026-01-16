-- ============================================================================
-- Admin Boundaries Areas Materialized Views Pyramid
-- ============================================================================

/**
layers: admin_boundaries_areas
tegola_config: config/providers/admin_boundaries_polygon.toml
## filters_per_zoom_level:
- z16-20: mv_admin_boundaries_areas_z16_20 | tolerance=1m | min_area=0 | filter=admin_level IN (1,2,3,4,5,6,7,8,9,10,11) | source=osm_admin_areas
- z13-15: mv_admin_boundaries_areas_z13_15 | tolerance=5m | min_area=0 | filter=(inherited from z16-20) | source=mv_admin_boundaries_areas_z16_20
- z10-12: mv_admin_boundaries_areas_z10_12 | tolerance=20m| min_area=0 | filter=admin_level IN (1,2,3,4,5,6,7,8,9,10) | source=mv_admin_boundaries_areas_z13_15
- z8-9:   mv_admin_boundaries_areas_z8_9   | tolerance=100m| min_area=0 | filter=admin_level IN (1,2,3,4,5,6,7,8,9) | source=mv_admin_boundaries_areas_z10_12
- z6-7:   mv_admin_boundaries_areas_z6_7   | tolerance=200m| min_area=0 | filter=admin_level IN (1,2,3,4,5,6) | source=mv_admin_boundaries_areas_z8_9
- z3-5:   mv_admin_boundaries_areas_z3_5   | tolerance=1000m| min_area=0 | filter=admin_level IN (1,2,3,4) | source=mv_admin_boundaries_areas_z6_7
- z0-2:   mv_admin_boundaries_areas_z0_2   | tolerance=5000m| min_area=0 | filter=admin_level IN (1,2) | source=mv_admin_boundaries_areas_z3_5

## description:
OpenhistoricalMap admin boundaries, contains administrative boundaries (countries, regions, etc.) in polygon format

## details:
- This layer contains the administrative boundaries (countries, regions, etc.) in polygon format
**/

DROP FUNCTION MATERIALIZED VIEW IF EXISTS mv_admin_boundaries_areas_z16_20 CASCADE;

SELECT create_areas_mview( 'osm_admin_areas', 'mv_admin_boundaries_areas_z16_20', 1, 0, 'id, osm_id, type', 'admin_level IN (1,2,3,4,5,6,7,8,9,10,11)');
SELECT create_area_mview_from_mview('mv_admin_boundaries_areas_z16_20','mv_admin_boundaries_areas_z13_15', 5, 0.0, NULL);
SELECT create_area_mview_from_mview('mv_admin_boundaries_areas_z13_15','mv_admin_boundaries_areas_z10_12', 20, 0.0, 'admin_level IN (1,2,3,4,5,6,7,8,9,10)');
SELECT create_area_mview_from_mview('mv_admin_boundaries_areas_z10_12','mv_admin_boundaries_areas_z8_9', 100, 0.0, 'admin_level IN (1,2,3,4,5,6,7,8,9)');
SELECT create_area_mview_from_mview('mv_admin_boundaries_areas_z8_9','mv_admin_boundaries_areas_z6_7', 200, 0.0, 'admin_level IN (1,2,3,4,5,6)');
SELECT create_area_mview_from_mview('mv_admin_boundaries_areas_z6_7','mv_admin_boundaries_areas_z3_5', 1000, 0.0, 'admin_level IN (1,2,3,4)');
SELECT create_area_mview_from_mview('mv_admin_boundaries_areas_z3_5','mv_admin_boundaries_areas_z0_2', 5000, 0.0, 'admin_level IN (1,2)');


Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z0_2;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z3_5;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z16_20;
