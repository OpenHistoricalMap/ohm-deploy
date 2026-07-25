-- Create materialized views for other areas with different simplification levels
-- Using the generalized create_area_mview function

-- ============================================================================
-- Zoom 8-9:
-- Medium simplification (50m)
-- Medium areas (>1M m² = 1 km²)
-- ============================================================================
SELECT create_area_mview(
    source           => 'osm_other_areas',
    target           => 'mv_other_areas_z8_9',
    simplify_tol     => 100,
    min_metric       => 1000000,
    column_overrides => '{
        "religion": "NULLIF(tags->''religion'', '''')",
        "denomination": "NULLIF(tags->''denomination'', '''')"
    }'::jsonb
);
SELECT derive_centroid_mview(
    source           => 'mv_other_areas_z8_9',
    target           => 'mv_other_points_centroids_z8_9',
    require_name     => TRUE
);

-- ============================================================================
-- Zoom 10-12
-- ============================================================================
SELECT create_area_mview(
    source           => 'osm_other_areas',
    target           => 'mv_other_areas_z10_12',
    simplify_tol     => 20,
    min_metric       => 50000,
    column_overrides => '{
        "religion": "NULLIF(tags->''religion'', '''')",
        "denomination": "NULLIF(tags->''denomination'', '''')"
    }'::jsonb
);
SELECT derive_centroid_mview(
    source           => 'mv_other_areas_z10_12',
    target           => 'mv_other_points_centroids_z10_12',
    require_name     => TRUE
);

-- ============================================================================
-- Prepare points materialized view for higher zoom levels (12+)
-- ============================================================================
-- Prepare points table with necessary columns (start_decdate, end_decdate, area_m2, area_km2, etc.)
-- This must be done before creating centroids views that include points
SELECT create_point_mview(
    source           => 'osm_other_points',
    target           => 'mv_other_points',
    column_overrides => '{
        "religion": "NULLIF(tags->''religion'', '''')",
        "denomination": "NULLIF(tags->''denomination'', '''')"
    }'::jsonb
);


-- ============================================================================
-- Zoom 13-15:
-- ============================================================================
SELECT create_area_mview(
    source           => 'osm_other_areas',
    target           => 'mv_other_areas_z13_15',
    simplify_tol     => 5,
    min_metric       => 5000,
    column_overrides => '{
        "religion": "NULLIF(tags->''religion'', '''')",
        "denomination": "NULLIF(tags->''denomination'', '''')"
    }'::jsonb
);
SELECT derive_centroid_mview(
    source           => 'mv_other_areas_z13_15',
    target           => 'mv_other_points_centroids_z13_15',
    union_source     => 'mv_other_points',
    require_name     => TRUE
);

-- ============================================================================
-- Zoom 16-20:
-- No simplification
-- All areas
-- Include other points
-- ============================================================================
SELECT create_area_mview(
    source           => 'osm_other_areas',
    target           => 'mv_other_areas_z16_20',
    column_overrides => '{
        "religion": "NULLIF(tags->''religion'', '''')",
        "denomination": "NULLIF(tags->''denomination'', '''')"
    }'::jsonb
);
SELECT derive_centroid_mview(
    source           => 'mv_other_areas_z16_20',
    target           => 'mv_other_points_centroids_z16_20',
    union_source     => 'mv_other_points',
    require_name     => TRUE
);

-- ============================================================================
-- Create materialized views for other lines
-- ============================================================================
SELECT create_line_mview(
    source           => 'osm_other_lines',
    target           => 'mv_other_lines_z16_20'
);
SELECT derive_line_mview(
    source           => 'mv_other_lines_z16_20',
    target           => 'mv_other_lines_z14_15',
    simplify_tol     => 5
);
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
