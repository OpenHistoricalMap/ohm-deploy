-- ============================================================================
-- Natural Lines Materialized Views for Multiple Zoom Levels
-- Natural line features (natural=cliff, ...) split out of water_lines so they
-- are not tied to the water layer (issue #1345). Source table: osm_natural_lines.
-- The base type filter is kept explicit so new natural line types can be added
-- to the import without automatically showing up at every zoom.
-- ============================================================================

DROP MATERIALIZED VIEW IF EXISTS mv_natural_lines_z16_20 CASCADE;

SELECT create_line_mview(
    source           => 'osm_natural_lines',
    target           => 'mv_natural_lines_z16_20',
    where_filter     => 'type IN (''cliff'')'
);
SELECT derive_line_mview(
    source           => 'mv_natural_lines_z16_20',
    target           => 'mv_natural_lines_z13_15',
    simplify_tol     => 5,
    where_filter     => 'type IN (''cliff'')'
);
SELECT derive_line_mview(
    source           => 'mv_natural_lines_z13_15',
    target           => 'mv_natural_lines_z10_12',
    simplify_tol     => 20,
    where_filter     => 'type IN (''cliff'')'
);
-- Refresh lines views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_natural_lines_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_natural_lines_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_natural_lines_z10_12;
