
-- ============================================================================
-- Landuse Areas
-- Create  landuse areas materialized views with simplification and filtering
-- Exclude natrual=water https://github.com/OpenHistoricalMap/issues/issues/1197
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS mv_landuse_areas_z16_20 CASCADE;


SELECT create_areas_mview( 'osm_landuse_areas', 'mv_landuse_areas_z16_20', 0, 0, 'id, osm_id, type', 'NOT (type = ''water'' AND class = ''natural'')');
SELECT create_area_mview_from_mview('mv_landuse_areas_z16_20', 'mv_landuse_areas_z13_15', 5, 10000, NULL);
SELECT create_area_mview_from_mview('mv_landuse_areas_z13_15', 'mv_landuse_areas_z10_12', 20, 50000, NULL);
SELECT create_area_mview_from_mview('mv_landuse_areas_z10_12', 'mv_landuse_areas_z8_9', 100, 1000000, NULL);
SELECT create_area_mview_from_mview('mv_landuse_areas_z8_9', 'mv_landuse_areas_z6_7', 200, 10000000, NULL);


-- ============================================================================
-- Landuse centroids
-- Create points materialized view to add laater with centroids
-- Exclude natrual=water https://github.com/OpenHistoricalMap/issues/issues/1197
-- ============================================================================
SELECT create_points_mview('osm_landuse_points','mv_landuse_points' );
-- Create points centroids materialized views, add points  only for higher zoom levels
SELECT create_points_centroids_mview('mv_landuse_areas_z16_20','mv_landuse_points_centroids_z16_20','mv_landuse_points');
SELECT create_points_centroids_mview( 'mv_landuse_areas_z13_15', 'mv_landuse_points_centroids_z13_15', 'mv_landuse_points');
SELECT create_points_centroids_mview( 'mv_landuse_areas_z8_9', 'mv_landuse_points_centroids_z8_9', NULL);
SELECT create_points_centroids_mview( 'mv_landuse_areas_z6_7', 'mv_landuse_points_centroids_z6_7', NULL);


-- ============================================================================
-- Landuse lines
-- Create materialized views for landuse lines, 
-- Only tree_row type is used in the map style
-- ============================================================================
SELECT create_lines_mview('osm_landuse_lines', 'mv_landuse_lines_z16_20', 5, 0, 'id, osm_id, type', 'type IN (''tree_row'')');
SELECT create_mview_line_from_mview('mv_landuse_lines_z16_20', 'mv_landuse_lines_z14_15', 5, NULL);
