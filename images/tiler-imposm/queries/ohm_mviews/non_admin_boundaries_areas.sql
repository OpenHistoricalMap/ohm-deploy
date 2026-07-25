-- ============================================================================
-- Create materialized  views for non-admin boundaries areas https://github.com/OpenHistoricalMap/issues/issues/1251
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS mv_non_admin_boundaries_areas_z16_20 CASCADE;

SELECT create_area_mview(
    source           => 'osm_admin_areas',
    target           => 'mv_non_admin_boundaries_areas_z16_20',
    simplify_tol     => 1,
    where_filter     => 'type  <> ''administrative''',
    column_overrides => '{
        "religion": "tags->''religion''",
        "denomination": "tags->''denomination''",
        "timezone": "tags->''timezone''",
        "utc": "tags->''utc''",
        "postal_code": "tags->''postal_code''",
        "ref": "tags->''ref''",
        "political_division": "tags->''political_division''"
    }'::jsonb
);
SELECT derive_area_mview(
    source           => 'mv_non_admin_boundaries_areas_z16_20',
    target           => 'mv_non_admin_boundaries_areas_z13_15',
    simplify_tol     => 5
);
SELECT derive_area_mview(
    source           => 'mv_non_admin_boundaries_areas_z13_15',
    target           => 'mv_non_admin_boundaries_areas_z10_12',
    simplify_tol     => 20
);
SELECT derive_area_mview(
    source           => 'mv_non_admin_boundaries_areas_z10_12',
    target           => 'mv_non_admin_boundaries_areas_z8_9',
    simplify_tol     => 100
);
SELECT derive_area_mview(
    source           => 'mv_non_admin_boundaries_areas_z8_9',
    target           => 'mv_non_admin_boundaries_areas_z6_7',
    simplify_tol     => 200
);
SELECT derive_area_mview(
    source           => 'mv_non_admin_boundaries_areas_z6_7',
    target           => 'mv_non_admin_boundaries_areas_z3_5',
    simplify_tol     => 1000
);
SELECT derive_area_mview(
    source           => 'mv_non_admin_boundaries_areas_z3_5',
    target           => 'mv_non_admin_boundaries_areas_z0_2',
    simplify_tol     => 5000
);
-- ============================================================================
-- Centroids views for non-admin boundaries areas
-- ============================================================================

SELECT derive_centroid_mview(
    source           => 'mv_non_admin_boundaries_areas_z16_20',
    target           => 'mv_non_admin_boundaries_centroids_z16_20',
    require_name     => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_non_admin_boundaries_areas_z13_15',
    target           => 'mv_non_admin_boundaries_centroids_z13_15',
    require_name     => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_non_admin_boundaries_areas_z10_12',
    target           => 'mv_non_admin_boundaries_centroids_z10_12',
    require_name     => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_non_admin_boundaries_areas_z8_9',
    target           => 'mv_non_admin_boundaries_centroids_z8_9',
    require_name     => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_non_admin_boundaries_areas_z6_7',
    target           => 'mv_non_admin_boundaries_centroids_z6_7',
    require_name     => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_non_admin_boundaries_areas_z3_5',
    target           => 'mv_non_admin_boundaries_centroids_z3_5',
    require_name     => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_non_admin_boundaries_areas_z0_2',
    target           => 'mv_non_admin_boundaries_centroids_z0_2',
    require_name     => TRUE
);
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z3_5;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z0_2;

-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z3_5;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z0_2;
