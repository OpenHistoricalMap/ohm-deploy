-- Create materialized views for landuse areas with different simplification levels
-- Using the generalized create_areas_mview function

-- ============================================================================
-- Zoom 6-7:
-- Medium-high simplification (100m)
-- Medium-large areas (>10M m² = 10 km²)
-- Exclude water areas and natural areas, which are handled by the water_areas view
-- Exclude natrual=water https://github.com/OpenHistoricalMap/issues/issues/1197
-- ============================================================================
SELECT create_areas_mview(
    'osm_landuse_areas',
    'mv_landuse_areas_z6_7',
    200,
    10000000,
    'id, osm_id, type',
    'NOT (type = ''water'' AND class = ''natural'')'
);
SELECT create_points_centroids_mview(
    'mv_landuse_areas_z6_7',
    'mv_landuse_points_centroids_z6_7',
    NULL
);

-- ============================================================================
-- Zoom 8-9:
-- Medium simplification (50m)
-- Medium areas (>1M m² = 1 km²)
-- Exclude water areas and natural areas, which are handled by the water_areas view
-- Exclude natrual=water https://github.com/OpenHistoricalMap/issues/issues/1197
-- ============================================================================
SELECT create_areas_mview(
    'osm_landuse_areas',
    'mv_landuse_areas_z8_9',
    100,
    1000000,
    'id, osm_id, type',
    'NOT (type = ''water'' AND class = ''natural'')'
);
SELECT create_points_centroids_mview(
    'mv_landuse_areas_z8_9',
    'mv_landuse_points_centroids_z8_9',
    NULL
);

-- ============================================================================
-- Zoom 10-11:
-- Medium-low simplification (15m)
-- Medium areas (>50K m² = 0.05 km²)
-- Exclude water areas and natural areas, which are handled by the water_areas view
-- Exclude natrual=water https://github.com/OpenHistoricalMap/issues/issues/1197
-- ============================================================================
SELECT create_areas_mview(
    'osm_landuse_areas',
    'mv_landuse_areas_z10_12',
    20,
    50000,
    'id, osm_id, type',
    'NOT (type = ''water'' AND class = ''natural'')'
);
SELECT create_points_centroids_mview(
    'mv_landuse_areas_z10_12',
    'mv_landuse_points_centroids_z10_12',
    NULL
);


-- ============================================================================
-- Prepare points materialized view for higher zoom levels (12+)
-- ============================================================================
-- Prepare points table with necessary columns (start_decdate, end_decdate, area_m2, area_km2, etc.)
-- This must be done before creating centroids views that include points
SELECT create_points_mview(
    'osm_landuse_points',
    'mv_landuse_points'
);


-- ============================================================================
-- Zoom 13-15:
-- Low simplification (10m)
-- Small areas (>10K m² = 0.01 km²)
-- Exclude water areas and natural areas, which are handled by the water_areas view
-- Include landuse points
-- ============================================================================
SELECT create_areas_mview(
    'osm_landuse_areas',
    'mv_landuse_areas_z13_15',
    5,
    10000,
    'id, osm_id, type',
    'NOT (type = ''water'' AND class = ''natural'')'
);
SELECT create_points_centroids_mview(
    'mv_landuse_areas_z13_15',
    'mv_landuse_points_centroids_z13_15',
    'mv_landuse_points'
);

-- ============================================================================
-- Zoom 16-20:
-- No simplification
-- All areas
-- Exclude water areas and natural areas, which are handled by the water_areas view
-- Include landuse points
-- ============================================================================
SELECT create_areas_mview(
    'osm_landuse_areas',
    'mv_landuse_areas_z16_20',
    0,
    0,
    'id, osm_id, type',
    'NOT (type = ''water'' AND class = ''natural'')'
);
SELECT create_points_centroids_mview(
    'mv_landuse_areas_z16_20',
    'mv_landuse_points_centroids_z16_20',
    'mv_landuse_points'
);



-- Parameters:
--   source_table    TEXT              - Name of the source table or materialized view
--   view_name       TEXT              - Name of the materialized view to create
--   simplify_tol    DOUBLE PRECISION  - Simplification tolerance (0 = no simplification)
--   min_length      DOUBLE PRECISION  - Minimum length in m to include (0 = no filter)
--   unique_columns  TEXT              - Comma-separated columns for unique index (default: 'id, osm_id, type')
--   where_filter    TEXT              - Optional WHERE clause filter (e.g., "highway != 'abandoned'"). NULL = no filter
--
-- Notes:
--   - Creates the materialized view using a temporary swap mechanism
--   - Adds a spatial index (GiST) on geometry and a unique index on unique_columns
--   - Useful for creating views at different zoom levels with variable simplification
--   - where_filter is appended to WHERE clause with AND
-- -- ============================================================================
-- DROP FUNCTION IF EXISTS create_lines_mview(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT);

-- CREATE OR REPLACE FUNCTION create_lines_mview(
--     source_table TEXT,
--     view_name TEXT,
--     simplify_tol DOUBLE PRECISION DEFAULT 0,
--     min_length DOUBLE PRECISION DEFAULT 0,
--     unique_columns TEXT DEFAULT 'id, osm_id, type',
--     where_filter TEXT DEFAULT NULL
-- )


-- ============================================================================
-- Create materialized views for landuse lines, 
-- Only tree_row type is used in the map style
-- ============================================================================
SELECT create_lines_mview('osm_landuse_lines', 'mv_landuse_lines_z16_20', 5, 0, 'id, osm_id, type', 'type IN (''tree_row'')');
SELECT create_mview_line_from_mview('mv_landuse_lines_z16_20', 'mv_landuse_lines_z14_15', 5, NULL);


-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_landuse_areas_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_landuse_areas_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_landuse_areas_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_landuse_areas_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_landuse_areas_z6_7;

-- Refresh points centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_landuse_points_centroids_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_landuse_points_centroids_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_landuse_points_centroids_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_landuse_points;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_landuse_points_centroids_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_landuse_points_centroids_z16_20;

-- Refresh lines views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_landuse_lines_z14_20;
