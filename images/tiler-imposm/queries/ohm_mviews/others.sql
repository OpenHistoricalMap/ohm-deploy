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
    100,
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
-- Zoom 10-12
-- ============================================================================
SELECT create_areas_mview(
    'osm_other_areas',
    'mv_other_areas_z10_12',
    20,
    50000,
    'id, osm_id, type',
    NULL
);
SELECT create_points_centroids_mview(
    'mv_other_areas_z10_12',
    'mv_other_points_centroids_z10_12',
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
-- Zoom 13-15:
-- ============================================================================
SELECT create_areas_mview(
    'osm_other_areas',
    'mv_other_areas_z13_15',
    5,
    5000,
    'id, osm_id, type',
    NULL
);
SELECT create_points_centroids_mview(
    'mv_other_areas_z13_15',
    'mv_other_points_centroids_z13_15',
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
SELECT create_lines_mview('osm_other_lines', 'mv_other_lines_z16_20', 0, 0, 'id, osm_id, type');
SELECT create_mview_line_from_mview('mv_other_lines_z16_20', 'mv_other_lines_z14_15', 5);

-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_areas_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_areas_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_areas_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_areas_z16_20;

-- Refresh centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_points_centroids_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_points_centroids_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_points_centroids_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_points_centroids_z16_20;

-- Refresh lines views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_lines_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_lines_z14_15;

