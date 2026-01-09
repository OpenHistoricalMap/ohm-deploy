-- ============================================================================
-- Prepare points materialized view for higher zoom levels (12+)
-- ============================================================================
SELECT create_points_mview(
    'osm_amenity_points',
    'mv_amenity_points'
);

-- ============================================================================
-- Zoom 14-15:
-- Very low simplification (5m)
-- Very small areas (>5K m² = 0.005 km²)
-- ============================================================================
SELECT create_areas_mview(
    'osm_amenity_areas',
    'mv_amenity_areas_z14_15',
    5,
    5000,
    'id, osm_id, type',
    NULL
);
SELECT create_points_centroids_mview(
    'mv_amenity_areas_z14_15',
    'mv_amenity_points_centroids_z14_15',
    'mv_amenity_points'
);

-- ============================================================================
-- Zoom 16-20:
-- No simplification
-- All areas
-- ============================================================================
SELECT create_areas_mview(
    'osm_amenity_areas',
    'mv_amenity_areas_z16_20',
    0,
    0,
    'id, osm_id, type',
    NULL
);
SELECT create_points_centroids_mview(
    'mv_amenity_areas_z16_20',
    'mv_amenity_points_centroids_z16_20',
    'mv_amenity_points'
);

-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_amenity_areas_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_amenity_areas_z16_20;

-- Refresh centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_amenity_points_centroids_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_amenity_points_centroids_z16_20;
