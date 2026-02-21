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
        isodatetodecimaldate(pad_date(start_date::TEXT, 'start')::TEXT, FALSE) AS start_decdate,
        isodatetodecimaldate(pad_date(end_date::TEXT, 'end')::TEXT, FALSE) AS end_decdate,
        NULLIF(communication_telephone, '') AS communication_telephone,
        NULLIF(communication_telegraph, '') AS communication_telegraph,
        NULLIF(communication_internet, '') AS communication_internet,
        NULLIF(communication_cable_television, '') AS communication_cable_television,
        NULLIF(communication_television, '') AS communication_television,
        NULLIF(communication_radio, '') AS communication_radio,
        NULLIF(communication_microwave, '') AS communication_microwave,
        NULLIF(communication_bos, '') AS communication_bos,
        NULLIF(communication_mobile_phone, '') AS communication_mobile_phone,
        NULLIF(communication_satellite, '') AS communication_satellite,
        NULLIF(communication_amateur_radio, '') AS communication_amateur_radio,
        NULLIF(communication_optical, '') AS communication_optical,
        NULLIF(communication_space, '') AS communication_space,
        NULLIF(communication_gsm_r, '') AS communication_gsm_r,
        NULLIF(telecom, '') AS telecom,
        NULLIF(operator, '') AS operator,
        NULLIF(location, '') AS location,
        NULLIF(layer, '') AS layer,
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
        isodatetodecimaldate(pad_date(start_date::TEXT, 'start')::TEXT, FALSE) AS start_decdate,
        isodatetodecimaldate(pad_date(end_date::TEXT, 'end')::TEXT, FALSE) AS end_decdate,
        NULLIF(communication_telephone, '') AS communication_telephone,
        NULLIF(communication_telegraph, '') AS communication_telegraph,
        NULLIF(communication_internet, '') AS communication_internet,
        NULLIF(communication_cable_television, '') AS communication_cable_television,
        NULLIF(communication_television, '') AS communication_television,
        NULLIF(communication_radio, '') AS communication_radio,
        NULLIF(communication_microwave, '') AS communication_microwave,
        NULLIF(communication_bos, '') AS communication_bos,
        NULLIF(communication_mobile_phone, '') AS communication_mobile_phone,
        NULLIF(communication_satellite, '') AS communication_satellite,
        NULLIF(communication_amateur_radio, '') AS communication_amateur_radio,
        NULLIF(communication_optical, '') AS communication_optical,
        NULLIF(communication_space, '') AS communication_space,
        NULLIF(communication_gsm_r, '') AS communication_gsm_r,
        NULLIF(telecom, '') AS telecom,
        NULLIF(operator, '') AS operator,
        NULLIF(location, '') AS location,
        NULLIF(layer, '') AS layer,
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
