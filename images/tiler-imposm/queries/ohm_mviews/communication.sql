-- ============================================================================
-- Create materialized views for communication lines
-- Uses create_lines_mview to build views at different zoom levels
-- from the osm_communication_lines table (communication=line ways)
-- ============================================================================

-- ============================================================================
-- Zoom 16-20: No simplification, all features
-- ============================================================================
SELECT create_lines_mview(
    'osm_communication_lines',
    'mv_communication_z16_20',
    0,
    0,
    'id, osm_id, type'
);

-- ============================================================================
-- Zoom 14-15: Slight simplification (5m tolerance)
-- ============================================================================
SELECT create_mview_line_from_mview(
    'mv_communication_z16_20',
    'mv_communication_z14_15',
    5
);

-- Refresh views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_communication_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_communication_z14_15;
