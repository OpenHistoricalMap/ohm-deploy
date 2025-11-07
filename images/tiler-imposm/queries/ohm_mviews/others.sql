-- Create materialized views for other areas with different simplification levels
-- Using the generalized create_areas_mview function

-- ============================================================================
-- Zoom 8-9:
-- Medium simplification (50m)
-- Medium areas (>1M m² = 1 km²)
-- ============================================================================
SELECT create_areas_mview(
    'osm_other_areas',
    'mv_other_areas_z8_9',
    50,
    1000000,
    'id, osm_id, type',
    NULL
);
SELECT create_points_centroids_mview(
    'mv_other_areas_z8_9',
    'mv_other_points_centroids_z8_9',
    NULL
);

-- ============================================================================
-- Zoom 10-11:
-- Medium-low simplification (15m)
-- Medium areas (>50K m² = 0.05 km²)
-- ============================================================================
SELECT create_areas_mview(
    'osm_other_areas',
    'mv_other_areas_z10_11',
    15,
    50000,
    'id, osm_id, type',
    NULL
);
SELECT create_points_centroids_mview(
    'mv_other_areas_z10_11',
    'mv_other_points_centroids_z10_11',
    NULL
);

-- ============================================================================
-- Prepare points materialized view for higher zoom levels (12+)
-- ============================================================================
-- Prepare points table with necessary columns (start_decdate, end_decdate, area_m2, area_km2, etc.)
-- This must be done before creating centroids views that include points
SELECT create_points_mview(
    'osm_other_points',
    'mv_other_points'
);

-- ============================================================================
-- Zoom 12-13:
-- Low simplification (10m)
-- Small areas (>10K m² = 0.01 km²)
-- Include other points
-- ============================================================================
SELECT create_areas_mview(
    'osm_other_areas',
    'mv_other_areas_z12_13',
    10,
    10000,
    'id, osm_id, type',
    NULL
);
SELECT create_points_centroids_mview(
    'mv_other_areas_z12_13',
    'mv_other_points_centroids_z12_13',
    'mv_other_points'
);

-- ============================================================================
-- Zoom 14-15:
-- Very low simplification (5m)
-- Very small areas (>5K m² = 0.005 km²)
-- Include other points
-- ============================================================================
SELECT create_areas_mview(
    'osm_other_areas',
    'mv_other_areas_z14_15',
    5,
    5000,
    'id, osm_id, type',
    NULL
);
SELECT create_points_centroids_mview(
    'mv_other_areas_z14_15',
    'mv_other_points_centroids_z14_15',
    'mv_other_points'
);

-- ============================================================================
-- Zoom 16-20:
-- No simplification
-- All areas
-- Include other points
-- ============================================================================
SELECT create_areas_mview(
    'osm_other_areas',
    'mv_other_areas_z16_20',
    0,
    0,
    'id, osm_id, type',
    NULL
);
SELECT create_points_centroids_mview(
    'mv_other_areas_z16_20',
    'mv_other_points_centroids_z16_20',
    'mv_other_points'
);

-- ============================================================================
-- Create materialized views for other lines
-- ============================================================================
SELECT create_generic_mview('osm_other_lines', 'mv_other_lines_z14_20', ARRAY['osm_id', 'type', 'class']);