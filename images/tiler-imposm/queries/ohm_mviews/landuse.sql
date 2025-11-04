-- ============================================================================
-- Create materialized views for landuse areas with different simplification levels
-- Using the generalized create_simplified_mview function
--
-- This script creates simplified materialized views for different zoom levels,
-- each with appropriate geometry simplification and area filtering. For zoom
-- levels 13-15 and 16-20, point features are also included via UNION ALL.
-- ============================================================================

-- ============================================================================
-- Zoom 3-5: High simplification (200m), large areas only (>50M m² = 50 km²), Create centroids view from simplified areas (no points at this zoom level)
-- ============================================================================
SELECT create_simplified_mview('osm_landuse_areas', 'mv_landuse_areas_z3_5', 200, 50000000, 'id, osm_id, type');
SELECT create_centroids_mview('mv_landuse_areas_z3_5', 'mv_landuse_centroids_z3_5', NULL);

-- ============================================================================
-- Zoom 6-7: Medium-high simplification (100m), medium-large areas (>10M m² = 10 km²)
-- ============================================================================
SELECT create_simplified_mview('osm_landuse_areas', 'mv_landuse_areas_z6_7', 100, 10000000, 'id, osm_id, type');
SELECT create_centroids_mview('mv_landuse_areas_z6_7', 'mv_landuse_centroids_z6_7', NULL);

-- ============================================================================
-- Zoom 8-9: Medium simplification (50m), medium areas (>1M m² = 1 km²)
-- ============================================================================
SELECT create_simplified_mview('osm_landuse_areas', 'mv_landuse_areas_z8_9', 50, 1000000, 'id, osm_id, type');
SELECT create_centroids_mview('mv_landuse_areas_z8_9', 'mv_landuse_centroids_z8_9', NULL);

-- ============================================================================
-- Zoom 10-12: Low simplification (20m), small-medium areas (>100K m² = 0.1 km²)
-- ============================================================================
SELECT create_simplified_mview('osm_landuse_areas', 'mv_landuse_areas_z10_12', 20, 100000, 'id, osm_id, type');
SELECT create_centroids_mview('mv_landuse_areas_z10_12', 'mv_landuse_centroids_z10_12', NULL);

-- ============================================================================
-- Prepare points materialized view for higher zoom levels (13+)
-- ============================================================================
-- Prepare points table with necessary columns (start_decdate, end_decdate, area_m2, area_km2, etc.)
-- This must be done before creating centroids views that include points
SELECT prepare_points_mview('osm_landuse_points', 'mv_landuse_points');

-- ============================================================================
-- Zoom 13-15: Very low simplification (5m), small areas (>10K m² = 0.01 km²)
-- ============================================================================
SELECT create_simplified_mview('osm_landuse_areas', 'mv_landuse_areas_z13_15', 5, 10000, 'id, osm_id, type');
SELECT create_centroids_mview('mv_landuse_areas_z13_15', 'mv_landuse_centroids_z13_15', 'mv_landuse_points');

-- ============================================================================
-- Zoom 16-20: No simplification, all areas
-- ============================================================================
SELECT create_simplified_mview('osm_landuse_areas', 'mv_landuse_areas_z16_20', 0, 0, 'id, osm_id, type');
SELECT create_centroids_mview('mv_landuse_areas_z16_20', 'mv_landuse_centroids_z16_20', 'mv_landuse_points');
