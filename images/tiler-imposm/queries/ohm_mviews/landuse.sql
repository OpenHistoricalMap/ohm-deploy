
-- ============================================================================
-- Landuse Areas
-- Create  landuse areas materialized views with simplification and filtering
-- Exclude natrual=water https://github.com/OpenHistoricalMap/issues/issues/1197
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS mv_landuse_areas_z16_20 CASCADE;


SELECT create_area_mview(
    source           => 'osm_landuse_areas',
    target           => 'mv_landuse_areas_z16_20',
    where_filter     => 'NOT (type = ''water'' AND class = ''natural'')',
    column_overrides => '{
        "religion": "NULLIF(tags->''religion'', '''')",
        "denomination": "NULLIF(tags->''denomination'', '''')"
    }'::jsonb
);
SELECT derive_area_mview(
    source           => 'mv_landuse_areas_z16_20',
    target           => 'mv_landuse_areas_z13_15',
    simplify_tol     => 5,
    min_metric       => 10000
);
SELECT derive_area_mview(
    source           => 'mv_landuse_areas_z13_15',
    target           => 'mv_landuse_areas_z10_12',
    simplify_tol     => 20,
    min_metric       => 50000
);
SELECT derive_area_mview(
    source           => 'mv_landuse_areas_z10_12',
    target           => 'mv_landuse_areas_z8_9',
    simplify_tol     => 100,
    min_metric       => 1000000
);
SELECT derive_area_mview(
    source           => 'mv_landuse_areas_z8_9',
    target           => 'mv_landuse_areas_z6_7',
    simplify_tol     => 200,
    min_metric       => 10000000
);
-- ============================================================================
-- Landuse centroids
-- Create points materialized view to add laater with centroids
-- Exclude natrual=water https://github.com/OpenHistoricalMap/issues/issues/1197
-- ============================================================================
SELECT create_point_mview(
    source           => 'osm_landuse_points',
    target           => 'mv_landuse_points',
    column_overrides => '{
        "religion": "NULLIF(tags->''religion'', '''')",
        "denomination": "NULLIF(tags->''denomination'', '''')"
    }'::jsonb
);
-- Create points centroids materialized views, add points  only for higher zoom levels
SELECT derive_centroid_mview(
    source           => 'mv_landuse_areas_z16_20',
    target           => 'mv_landuse_points_centroids_z16_20',
    union_source     => 'mv_landuse_points',
    only_named       => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_landuse_areas_z13_15',
    target           => 'mv_landuse_points_centroids_z13_15',
    union_source     => 'mv_landuse_points',
    only_named       => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_landuse_areas_z10_12',
    target           => 'mv_landuse_points_centroids_z10_12',
    only_named       => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_landuse_areas_z8_9',
    target           => 'mv_landuse_points_centroids_z8_9',
    only_named       => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_landuse_areas_z6_7',
    target           => 'mv_landuse_points_centroids_z6_7',
    only_named       => TRUE
);
-- ============================================================================
-- Landuse lines
-- Create materialized views for landuse lines,
-- Only tree_row type is used in the map style
-- ============================================================================
SELECT create_line_mview(
    source           => 'osm_landuse_lines',
    target           => 'mv_landuse_lines_z16_20',
    simplify_tol     => 5,
    where_filter     => 'type IN (''tree_row'')'
);
SELECT derive_line_mview(
    source           => 'mv_landuse_lines_z16_20',
    target           => 'mv_landuse_lines_z14_15',
    simplify_tol     => 5
);