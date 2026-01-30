-- ============================================================================
-- Create materialized  views for non-admin boundaries areas https://github.com/OpenHistoricalMap/issues/issues/1251
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS mv_non_admin_boundaries_areas_z16_20 CASCADE;

SELECT create_areas_mview( 'osm_admin_areas', 'mv_non_admin_boundaries_areas_z16_20', 1, 0, 'id, osm_id, type', 'type  <> ''administrative''');
SELECT create_area_mview_from_mview('mv_non_admin_boundaries_areas_z16_20','mv_non_admin_boundaries_areas_z13_15', 5, 0.0, NULL);
SELECT create_area_mview_from_mview('mv_non_admin_boundaries_areas_z13_15','mv_non_admin_boundaries_areas_z10_12', 20, 0.0, NULL );
SELECT create_area_mview_from_mview('mv_non_admin_boundaries_areas_z10_12','mv_non_admin_boundaries_areas_z8_9', 100, 0.0, NULL );
SELECT create_area_mview_from_mview('mv_non_admin_boundaries_areas_z8_9','mv_non_admin_boundaries_areas_z6_7', 200, 0.0, NULL );
SELECT create_area_mview_from_mview('mv_non_admin_boundaries_areas_z6_7','mv_non_admin_boundaries_areas_z3_5', 1000, 0.0, NULL );
SELECT create_area_mview_from_mview('mv_non_admin_boundaries_areas_z3_5','mv_non_admin_boundaries_areas_z0_2', 5000, 0.0, NULL );

-- ============================================================================
-- Centroids views for non-admin boundaries areas
-- ============================================================================

SELECT create_points_centroids_mview('mv_non_admin_boundaries_areas_z16_20', 'mv_non_admin_boundaries_centroids_z16_20', NULL);
SELECT create_points_centroids_mview('mv_non_admin_boundaries_areas_z13_15', 'mv_non_admin_boundaries_centroids_z13_15', NULL);
SELECT create_points_centroids_mview('mv_non_admin_boundaries_areas_z10_12', 'mv_non_admin_boundaries_centroids_z10_12', NULL);
SELECT create_points_centroids_mview('mv_non_admin_boundaries_areas_z8_9', 'mv_non_admin_boundaries_centroids_z8_9', NULL);
SELECT create_points_centroids_mview('mv_non_admin_boundaries_areas_z6_7', 'mv_non_admin_boundaries_centroids_z6_7', NULL);
SELECT create_points_centroids_mview('mv_non_admin_boundaries_areas_z3_5', 'mv_non_admin_boundaries_centroids_z3_5', NULL);
SELECT create_points_centroids_mview('mv_non_admin_boundaries_areas_z0_2', 'mv_non_admin_boundaries_centroids_z0_2', NULL);


-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z3_5;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z0_2;

-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z3_5;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z0_2;
