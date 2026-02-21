-- ============================================================================
-- Create materialized views for communication lines
-- Combines osm_communication_lines (ways) and osm_communication_multilines
-- (relation members) into unified views at different zoom levels.
-- ============================================================================

-- ============================================================================
-- Unified view: merge lines + multilines into a single source
-- TODO, Do we need to add name_lcale columns?
-- ============================================================================
DROP VIEW IF EXISTS mv_communication_z16_20 CASCADE;
CREATE VIEW mv_communication_z16_20 AS
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
