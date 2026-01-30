-- ============================================================================
-- Create materialized views for admin boundaries areas
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS mv_admin_boundaries_areas_z16_20 CASCADE;

SELECT create_areas_mview( 'osm_admin_areas', 'mv_admin_boundaries_areas_z16_20', 1, 0, 'id, osm_id, type', 'admin_level IN (1,2,3,4,5,6,7,8,9,10,11)');
SELECT create_area_mview_from_mview('mv_admin_boundaries_areas_z16_20','mv_admin_boundaries_areas_z13_15', 5, 0.0, NULL);
SELECT create_area_mview_from_mview('mv_admin_boundaries_areas_z13_15','mv_admin_boundaries_areas_z10_12', 20, 0.0, 'admin_level IN (1,2,3,4,5,6,7,8,9,10)');
SELECT create_area_mview_from_mview('mv_admin_boundaries_areas_z10_12','mv_admin_boundaries_areas_z8_9', 100, 0.0, 'admin_level IN (1,2,3,4,5,6,7,8,9)');
SELECT create_area_mview_from_mview('mv_admin_boundaries_areas_z8_9','mv_admin_boundaries_areas_z6_7', 200, 0.0, 'admin_level IN (1,2,3,4,5,6)');
SELECT create_area_mview_from_mview('mv_admin_boundaries_areas_z6_7','mv_admin_boundaries_areas_z3_5', 1000, 0.0, 'admin_level IN (1,2,3,4)');
SELECT create_area_mview_from_mview('mv_admin_boundaries_areas_z3_5','mv_admin_boundaries_areas_z0_2', 5000, 0.0, 'admin_level IN (1,2)');


-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z0_2;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z3_5;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z16_20;
