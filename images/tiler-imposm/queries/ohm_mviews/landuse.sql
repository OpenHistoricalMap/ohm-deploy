-- ============================================================================
-- Create materialized views for landuse areas with different simplification levels
-- Using the generalized create_areas_mview function
--
-- This script creates simplified materialized views for different zoom levels,
-- each with appropriate geometry simplification and area filtering. For zoom
-- levels 13-15 and 16-20, point features are also included via UNION ALL.
-- ============================================================================

-- ============================================================================
-- Zoom 3-5: High simplification (200m), large areas only (>50M m² = 50 km²), Create centroids view from simplified areas (no points at this zoom level)
-- ============================================================================
SELECT create_areas_mview('osm_landuse_areas', 'mv_landuse_areas_z3_5', 200, 50000000, 'id, osm_id, type');
SELECT create_points_centroids_mview('mv_landuse_areas_z3_5', 'mv_landuse_points_centroids_z3_5', NULL);

-- ============================================================================
-- Zoom 6-7: Medium-high simplification (100m), medium-large areas (>10M m² = 10 km²)
-- ============================================================================
SELECT create_areas_mview('osm_landuse_areas', 'mv_landuse_areas_z6_7', 100, 10000000, 'id, osm_id, type');
SELECT create_points_centroids_mview('mv_landuse_areas_z6_7', 'mv_landuse_points_centroids_z6_7', NULL);

-- ============================================================================
-- Zoom 8-9: Medium simplification (50m), medium areas (>1M m² = 1 km²)
-- ============================================================================
SELECT create_areas_mview('osm_landuse_areas', 'mv_landuse_areas_z8_9', 50, 1000000, 'id, osm_id, type');
SELECT create_points_centroids_mview('mv_landuse_areas_z8_9', 'mv_landuse_points_centroids_z8_9', NULL);

-- ============================================================================
-- Zoom 10-11: Medium-low simplification (15m), medium areas (>50K m² = 0.05 km²)
-- ============================================================================
SELECT create_areas_mview('osm_landuse_areas', 'mv_landuse_areas_z10_11', 15, 50000, 'id, osm_id, type');
SELECT create_points_centroids_mview('mv_landuse_areas_z10_11', 'mv_landuse_points_centroids_z10_11', NULL);


-- ============================================================================
-- Prepare points materialized view for higher zoom levels (12+)
-- ============================================================================
-- Prepare points table with necessary columns (start_decdate, end_decdate, area_m2, area_km2, etc.)
-- This must be done before creating centroids views that include points
SELECT create_points_mview('osm_landuse_points', 'mv_landuse_points');


-- ============================================================================
-- Zoom 12-13: Low simplification (10m), small areas (>10K m² = 0.01 km²)
-- ============================================================================
SELECT create_areas_mview('osm_landuse_areas', 'mv_landuse_areas_z12_13', 10, 10000, 'id, osm_id, type');
SELECT create_points_centroids_mview('mv_landuse_areas_z12_13', 'mv_landuse_points_centroids_z12_13', 'mv_landuse_points');


-- ============================================================================
-- Zoom 14-15: Very low simplification (5m), very small areas (>5K m² = 0.005 km²)
-- ============================================================================
SELECT create_areas_mview('osm_landuse_areas', 'mv_landuse_areas_z14_15', 5, 5000, 'id, osm_id, type');
SELECT create_points_centroids_mview('mv_landuse_areas_z14_15', 'mv_landuse_points_centroids_z14_15', 'mv_landuse_points');

-- ============================================================================
-- Zoom 16-20: No simplification, all areas
-- ============================================================================
SELECT create_areas_mview('osm_landuse_areas', 'mv_landuse_areas_z16_20', 0, 0, 'id, osm_id, type');
SELECT create_points_centroids_mview('mv_landuse_areas_z16_20', 'mv_landuse_points_centroids_z16_20', 'mv_landuse_points');


-- ============================================================================
-- Create materialized views for landuse lines
-- ============================================================================
SELECT create_generic_mview( 'osm_landuse_lines', 'mv_landuse_lines_z14_20', ARRAY['osm_id', 'type', 'class']);
