-- ============================================================================
-- Prepare points materialized view for higher zoom levels (12+)
-- Add height and height_fixed columns
-- ============================================================================
SELECT create_points_mview(
    'osm_buildings_points',
    'mv_buildings_points',
    'id, source, osm_id',
    ARRAY['NULL as height']
);



-- ============================================================================
-- Zoom 14-15:
-- Very low simplification (5m)
-- Very small areas (>5K m² = 0.005 km²)
-- Add height_fixed column
-- ============================================================================
SELECT create_areas_mview(
    'osm_buildings',
    'mv_buildings_areas_z14_15',
    5,
    5000,
    'id, osm_id, type',
    NULL
);

SELECT create_points_centroids_mview(
    'mv_buildings_areas_z14_15',
    'mv_buildings_points_centroids_z14_15',
    'mv_buildings_points'
);
-- ============================================================================
-- Zoom 16-20:
-- No simplification
-- All areas
-- Add height_fixed column
-- ============================================================================

SELECT create_areas_mview(
    'osm_buildings',
    'mv_buildings_areas_z16_20',
    0,
    0,
    'id, osm_id, type',
    NULL
);
SELECT create_points_centroids_mview(
    'mv_buildings_areas_z16_20',
    'mv_buildings_points_centroids_z16_20',
    'mv_buildings_points'
);

-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_areas_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_areas_z16_20;

-- Refresh centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_points_centroids_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_points_centroids_z16_20;
