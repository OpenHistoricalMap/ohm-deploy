-- Create materialized views for landuse areas with different simplification levels
-- Using the generalized create_areas_mview function

-- ============================================================================
-- Zoom 3-5:
-- High simplification (200m)
-- Large areas only (>50M m² = 50 km²)
-- Exclude water areas and natural areas, which are handled by the water_areas view
-- Create centroids view from simplified areas (no points at this zoom level)
-- ============================================================================
-- SELECT create_areas_mview(
--     'osm_landuse_areas',
--     'mv_landuse_areas_z3_5',
--     200,
--     50000000,
--     'id, osm_id, type',
--     'NOT (type = ''water'' AND class = ''natural'')'
-- );
-- SELECT create_points_centroids_mview(
--     'mv_landuse_areas_z3_5',
--     'mv_landuse_points_centroids_z3_5',
--     NULL
-- );

-- ============================================================================
-- Zoom 6-7:
-- Medium-high simplification (100m)
-- Medium-large areas (>10M m² = 10 km²)
-- Exclude water areas and natural areas, which are handled by the water_areas view
-- ============================================================================
SELECT create_areas_mview(
    'osm_landuse_areas',
    'mv_landuse_areas_z6_7',
    100,
    10000000,
    'id, osm_id, type',
    'NOT (type = ''water'' AND class = ''natural'')'
);
SELECT create_points_centroids_mview(
    'mv_landuse_areas_z6_7',
    'mv_landuse_points_centroids_z6_7',
    NULL
);

-- ============================================================================
-- Zoom 8-9:
-- Medium simplification (50m)
-- Medium areas (>1M m² = 1 km²)
-- Exclude water areas and natural areas, which are handled by the water_areas view
-- ============================================================================
SELECT create_areas_mview(
    'osm_landuse_areas',
    'mv_landuse_areas_z8_9',
    50,
    1000000,
    'id, osm_id, type',
    'NOT (type = ''water'' AND class = ''natural'')'
);
SELECT create_points_centroids_mview(
    'mv_landuse_areas_z8_9',
    'mv_landuse_points_centroids_z8_9',
    NULL
);

-- ============================================================================
-- Zoom 10-11:
-- Medium-low simplification (15m)
-- Medium areas (>50K m² = 0.05 km²)
-- Exclude water areas and natural areas, which are handled by the water_areas view
-- ============================================================================
SELECT create_areas_mview(
    'osm_landuse_areas',
    'mv_landuse_areas_z10_11',
    15,
    50000,
    'id, osm_id, type',
    'NOT (type = ''water'' AND class = ''natural'')'
);
SELECT create_points_centroids_mview(
    'mv_landuse_areas_z10_11',
    'mv_landuse_points_centroids_z10_11',
    NULL
);


-- ============================================================================
-- Prepare points materialized view for higher zoom levels (12+)
-- ============================================================================
-- Prepare points table with necessary columns (start_decdate, end_decdate, area_m2, area_km2, etc.)
-- This must be done before creating centroids views that include points
SELECT create_points_mview(
    'osm_landuse_points',
    'mv_landuse_points'
);


-- ============================================================================
-- Zoom 12-13:
-- Low simplification (10m)
-- Small areas (>10K m² = 0.01 km²)
-- Exclude water areas and natural areas, which are handled by the water_areas view
-- Include landuse points
-- ============================================================================
SELECT create_areas_mview(
    'osm_landuse_areas',
    'mv_landuse_areas_z12_13',
    10,
    10000,
    'id, osm_id, type',
    'NOT (type = ''water'' AND class = ''natural'')'
);
SELECT create_points_centroids_mview(
    'mv_landuse_areas_z12_13',
    'mv_landuse_points_centroids_z12_13',
    'mv_landuse_points'
);


-- ============================================================================
-- Zoom 14-15:
-- Very low simplification (5m)
-- Very small areas (>5K m² = 0.005 km²)
-- Exclude water areas and natural areas, which are handled by the water_areas view
-- Include landuse points
-- ============================================================================
SELECT create_areas_mview(
    'osm_landuse_areas',
    'mv_landuse_areas_z14_15',
    5,
    5000,
    'id, osm_id, type',
    'NOT (type = ''water'' AND class = ''natural'')'
);
SELECT create_points_centroids_mview(
    'mv_landuse_areas_z14_15',
    'mv_landuse_points_centroids_z14_15',
    'mv_landuse_points'
);

-- ============================================================================
-- Zoom 16-20:
-- No simplification
-- All areas
-- Exclude water areas and natural areas, which are handled by the water_areas view
-- Include landuse points
-- ============================================================================
SELECT create_areas_mview(
    'osm_landuse_areas',
    'mv_landuse_areas_z16_20',
    0,
    0,
    'id, osm_id, type',
    'NOT (type = ''water'' AND class = ''natural'')'
);
SELECT create_points_centroids_mview(
    'mv_landuse_areas_z16_20',
    'mv_landuse_points_centroids_z16_20',
    'mv_landuse_points'
);


-- ============================================================================
-- Create materialized views for landuse lines
-- ============================================================================
SELECT create_generic_mview(
    'osm_landuse_lines',
    'mv_landuse_lines_z14_20',
    ARRAY['osm_id', 'type', 'class']
);
