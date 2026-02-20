-- ============================================================================
-- Create materialized views for communication lines
-- Combines osm_communication_lines (ways) and osm_communication_multilines
-- (relation members) into unified views at different zoom levels.
-- ============================================================================

-- ============================================================================
-- Unified view: merge lines + multilines into a single source
-- ============================================================================
DROP VIEW IF EXISTS v_communication_combined CASCADE;
CREATE VIEW v_communication_combined AS
    -- Ways (simple linestrings)
    SELECT
        id,
        osm_id,
        geometry,
        name,
        type,
        start_date,
        end_date,
        communication_telephone,
        communication_telegraph,
        communication_internet,
        communication_cable_television,
        operator,
        location,
        layer,
        tags,
        'line' AS source_type
    FROM osm_communication_lines
    WHERE geometry IS NOT NULL

    UNION ALL

    -- Relation members (multilinestrings)
    SELECT
        id,
        osm_id,
        geometry,
        name,
        type,
        start_date,
        end_date,
        communication_telephone,
        communication_telegraph,
        communication_internet,
        communication_cable_television,
        operator,
        location,
        layer,
        tags,
        'relation' AS source_type
    FROM osm_communication_multilines
    WHERE geometry IS NOT NULL
      AND ST_GeometryType(geometry) IN ('ST_LineString', 'ST_MultiLineString');

-- ============================================================================
-- Zoom 16-20: No simplification, all features
-- ============================================================================
SELECT create_lines_mview(
    'v_communication_combined',
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
