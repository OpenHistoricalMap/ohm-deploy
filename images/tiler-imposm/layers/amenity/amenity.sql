-- ============================================================================
-- Prepare points materialized view for higher zoom levels (12+)
-- ============================================================================
SELECT create_point_mview(
    source           => 'osm_amenity_points',
    target           => 'mv_amenity_points',
    column_overrides => '{
        "religion": "NULLIF(tags->''religion'', '''')",
        "denomination": "NULLIF(tags->''denomination'', '''')"
    }'::jsonb
);

-- ============================================================================
-- Zoom 14-15:
-- Very low simplification (5m)
-- Very small areas (>5K m² = 0.005 km²)
-- ============================================================================
SELECT create_area_mview(
    source           => 'osm_amenity_areas',
    target           => 'mv_amenity_areas_z14_15',
    simplify_tol     => 5,
    min_metric       => 5000,
    column_overrides => '{
        "religion": "NULLIF(tags->''religion'', '''')",
        "denomination": "NULLIF(tags->''denomination'', '''')"
    }'::jsonb
);
SELECT derive_centroid_mview(
    source           => 'mv_amenity_areas_z14_15',
    target           => 'mv_amenity_points_centroids_z14_15',
    union_source     => 'mv_amenity_points',
    only_named       => TRUE
);

-- ============================================================================
-- Zoom 16-20:
-- No simplification
-- All areas
-- ============================================================================
SELECT create_area_mview(
    source           => 'osm_amenity_areas',
    target           => 'mv_amenity_areas_z16_20',
    column_overrides => '{
        "religion": "NULLIF(tags->''religion'', '''')",
        "denomination": "NULLIF(tags->''denomination'', '''')"
    }'::jsonb
);
SELECT derive_centroid_mview(
    source           => 'mv_amenity_areas_z16_20',
    target           => 'mv_amenity_points_centroids_z16_20',
    union_source     => 'mv_amenity_points',
    only_named       => TRUE
);

-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_amenity_areas_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_amenity_areas_z16_20;

-- Refresh centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_amenity_points_centroids_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_amenity_points_centroids_z16_20;
