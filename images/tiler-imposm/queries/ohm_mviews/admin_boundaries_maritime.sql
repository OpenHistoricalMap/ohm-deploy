-- ============================================================================
-- Create materialized views for maritime admin boundaries
-- ============================================================================
SELECT create_line_mview(
    source           => 'osm_admin_lines',
    target           => 'mv_admin_maritime_lines_z0_5_v2',
    simplify_tol     => 2000,
    where_filter     => 'maritime = ''yes'''
);

SELECT create_line_mview(
    source           => 'osm_admin_lines',
    target           => 'mv_admin_maritime_lines_z6_9',
    simplify_tol     => 500,
    where_filter     => 'maritime = ''yes'''
);

SELECT create_line_mview(
    source           => 'osm_admin_lines',
    target           => 'mv_admin_maritime_lines_z10_15',
    simplify_tol     => 10,
    where_filter     => 'maritime = ''yes'''
);

-- Refresh maritime lines views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_maritime_lines_z0_5_v2;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_maritime_lines_z6_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_maritime_lines_z10_15;
