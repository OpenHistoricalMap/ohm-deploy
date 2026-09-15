-- ============================================================================
-- Create materialized views for admin boundaries areas
-- ============================================================================

-- Index on admin_level to speed up filtering
CREATE INDEX IF NOT EXISTS idx_osm_admin_areas_admin_level
ON osm_admin_areas (admin_level) WHERE geometry IS NOT NULL;

-- Enable parallel workers on source table
ALTER TABLE osm_admin_areas SET (parallel_workers = 4);


SELECT create_area_mview(
    source           => 'osm_admin_areas',
    target           => 'mv_admin_boundaries_areas_z16_20',
    simplify_tol     => 1,
    where_filter     => 'admin_level IN (1,2,3,4,5,6,7,8,9,10,11)'
);
SELECT derive_area_mview(
    source           => 'mv_admin_boundaries_areas_z16_20',
    target           => 'mv_admin_boundaries_areas_z13_15',
    simplify_tol     => 5
);
SELECT derive_area_mview(
    source           => 'mv_admin_boundaries_areas_z13_15',
    target           => 'mv_admin_boundaries_areas_z10_12',
    simplify_tol     => 20,
    where_filter     => 'admin_level IN (1,2,3,4,5,6,7,8,9,10)'
);
SELECT derive_area_mview(
    source           => 'mv_admin_boundaries_areas_z10_12',
    target           => 'mv_admin_boundaries_areas_z8_9',
    simplify_tol     => 100,
    where_filter     => 'admin_level IN (1,2,3,4,5,6,7,8,9)'
);
SELECT derive_area_mview(
    source           => 'mv_admin_boundaries_areas_z8_9',
    target           => 'mv_admin_boundaries_areas_z6_7',
    simplify_tol     => 200,
    where_filter     => 'admin_level IN (1,2,3,4,5,6)'
);
SELECT derive_area_mview(
    source           => 'mv_admin_boundaries_areas_z6_7',
    target           => 'mv_admin_boundaries_areas_z3_5',
    simplify_tol     => 1000,
    where_filter     => 'admin_level IN (1,2,3,4)'
);
SELECT derive_area_mview(
    source           => 'mv_admin_boundaries_areas_z3_5',
    target           => 'mv_admin_boundaries_areas_z0_2',
    simplify_tol     => 5000,
    where_filter     => 'admin_level IN (1,2)'
);
-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z0_2;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z3_5;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_boundaries_areas_z16_20;
