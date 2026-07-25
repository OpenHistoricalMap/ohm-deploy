-- ============================================================================
-- Water Areas Materialized Views for Multiple Zoom Levels
-- Creates a pyramid of materialized views for water areas, optimized for
-- ============================================================================

-- Delete existing views, in cascade
DROP MATERIALIZED VIEW IF EXISTS mv_water_areas_z16_20 CASCADE;

SELECT create_area_mview(
    source           => 'osm_water_areas',
    target           => 'mv_water_areas_z16_20',
    column_overrides => '{"golf": "NULLIF(tags->''golf'', '''')"}'::jsonb
);
SELECT derive_area_mview(
    source           => 'mv_water_areas_z16_20',
    target           => 'mv_water_areas_z13_15',
    simplify_tol     => 5
);
SELECT derive_area_mview(
    source           => 'mv_water_areas_z13_15',
    target           => 'mv_water_areas_z10_12',
    simplify_tol     => 20,
    min_metric       => 100,
    where_filter     => 'type IN (''water'',''pond'',''basin'',''canal'',''mill_pond'',''riverbank'')'
);
SELECT derive_area_mview(
    source           => 'mv_water_areas_z10_12',
    target           => 'mv_water_areas_z8_9',
    simplify_tol     => 100,
    min_metric       => 10000
);
SELECT derive_area_mview(
    source           => 'mv_water_areas_z8_9',
    target           => 'mv_water_areas_z6_7',
    simplify_tol     => 200,
    min_metric       => 1000000
);
SELECT derive_area_mview(
    source           => 'mv_water_areas_z6_7',
    target           => 'mv_water_areas_z3_5',
    simplify_tol     => 1000,
    min_metric       => 50000000
);
SELECT derive_area_mview(
    source           => 'mv_water_areas_z3_5',
    target           => 'mv_water_areas_z0_2',
    simplify_tol     => 5000,
    min_metric       => 100000000,
    where_filter     => 'type IN (''water'',''riverbank'')'
);
-- ============================================================================
-- Water Areas Centroids Materialized Views for Multiple Zoom Levels
-- ============================================================================
SELECT derive_centroid_mview(
    source           => 'mv_water_areas_z16_20',
    target           => 'mv_water_areas_centroids_z16_20',
    where_filter     => 'name IS NOT NULL AND name <> '''''
);
SELECT derive_centroid_mview(
    source           => 'mv_water_areas_z13_15',
    target           => 'mv_water_areas_centroids_z13_15',
    where_filter     => 'name IS NOT NULL AND name <> '''''
);
SELECT derive_centroid_mview(
    source           => 'mv_water_areas_z10_12',
    target           => 'mv_water_areas_centroids_z10_12',
    where_filter     => 'name IS NOT NULL AND name <> '''''
);
SELECT derive_centroid_mview(
    source           => 'mv_water_areas_z8_9',
    target           => 'mv_water_areas_centroids_z8_9',
    where_filter     => 'name IS NOT NULL AND name <> '''''
);
-- ============================================================================
-- Water lines Materialized Views for Multiple Zoom Levels
-- ============================================================================

SELECT create_line_mview(
    source           => 'osm_water_lines',
    target           => 'mv_water_lines_z16_20',
    where_filter     => 'type IN (''river'', ''canal'', ''dam'', ''stream'', ''ditch'', ''drain'')'
);
SELECT derive_line_mview(
    source           => 'mv_water_lines_z16_20',
    target           => 'mv_water_lines_z13_15',
    simplify_tol     => 5,
    where_filter     => 'type IN (''river'', ''canal'', ''dam'', ''stream'')'
);
SELECT derive_line_mview(
    source           => 'mv_water_lines_z13_15',
    target           => 'mv_water_lines_z10_12',
    simplify_tol     => 20,
    where_filter     => 'type IN (''river'', ''canal'', ''dam'')'
);
SELECT derive_line_mview(
    source           => 'mv_water_lines_z10_12',
    target           => 'mv_water_lines_z8_9',
    simplify_tol     => 100,
    where_filter     => 'type IN (''river'', ''canal'')'
);
-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z3_5;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z0_2;

-- Refresh centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_areas_centroids_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_areas_centroids_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_areas_centroids_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_areas_centroids_z8_9;

-- Refresh lines views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_lines_z16_20
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_lines_z13_15
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_lines_z10_12
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_lines_z8_9
