-- ============================================================================
-- Natural Lines Materialized Views for Multiple Zoom Levels
-- Natural line features (natural=cliff, ...) split out of water_lines so they
-- are not tied to the water layer (issue #1345). Source table: osm_natural_lines.
-- The base type filter is kept explicit so new natural line types can be added
-- to the import without automatically showing up at every zoom.
-- ============================================================================

DROP MATERIALIZED VIEW IF EXISTS mv_natural_lines_z16_20 CASCADE;

SELECT create_lines_mview('osm_natural_lines', 'mv_natural_lines_z16_20', 0, 0, 'id, osm_id, type', 'type IN (''cliff'')');
SELECT create_mview_line_from_mview('mv_natural_lines_z16_20', 'mv_natural_lines_z13_15', 5, 'type IN (''cliff'')');
SELECT create_mview_line_from_mview('mv_natural_lines_z13_15', 'mv_natural_lines_z10_12', 20, 'type IN (''cliff'')');

-- Refresh lines views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_natural_lines_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_natural_lines_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_natural_lines_z10_12;
