/**
layers: other_areas
tegola_config: config/providers/other_areas.toml
filters_per_zoom_level:
- z16-20: mv_other_areas_z16_20 | tolerance=0m | min_area=0 | filter=(all)
- z13-15: mv_other_areas_z13_15 | tolerance=5m | min_area=5000 | filter=(all)
- z10-12: mv_other_areas_z10_12 | tolerance=20m | min_area=50000 | filter=(all)
- z8-9:   mv_other_areas_z8_9   | tolerance=100m | min_area=1000000 | filter=(all)

## description:
OpenhistoricalMap other areas, contains miscellaneous area features that don't fit into specific categories (catch-all layer)

## details:
- Catch-all layer for areas that don't fit into specific categories
**/

-- Create materialized views for other areas with different simplification levels
-- Using the generalized create_areas_mview function

-- ============================================================================
-- Zoom 8-9:
-- Medium simplification (50m)
-- Medium areas (>1M m² = 1 km²)
-- ============================================================================
SELECT create_areas_mview(
    'osm_other_areas',
    'mv_other_areas_z8_9',
    100,
    1000000,
    'id, osm_id, type',
    NULL
);
SELECT create_points_centroids_mview(
    'mv_other_areas_z8_9',
    'mv_other_points_centroids_z8_9',
    NULL
);

-- ============================================================================
-- Zoom 10-12
-- ============================================================================
SELECT create_areas_mview(
    'osm_other_areas',
    'mv_other_areas_z10_12',
    20,
    50000,
    'id, osm_id, type',
    NULL
);
SELECT create_points_centroids_mview(
    'mv_other_areas_z10_12',
    'mv_other_points_centroids_z10_12',
    NULL
);

/**
layers: other_points_centroids
tegola_config: config/providers/other_points_centroids.toml
filters_per_zoom_level:
- z16-20: mv_other_points_centroids_z16_20 | filter=(includes points from mv_other_points)
- z13-15: mv_other_points_centroids_z13_15 | filter=(includes points from mv_other_points)
- z10-12: mv_other_points_centroids_z10_12 | filter=(centroids only, no points)
- z8-9:   mv_other_points_centroids_z8_9   | filter=(centroids only, no points)

## description:
OpenhistoricalMap other points centroids, contains point representations of miscellaneous features (centroids from polygons and point features)

## details:
- Points centroids are created from areas and points for higher zoom levels
- Lower zoom levels show centroids only, no points
**/

-- ============================================================================
-- Prepare points materialized view for higher zoom levels (12+)
-- ============================================================================
-- Prepare points table with necessary columns (start_decdate, end_decdate, area_m2, area_km2, etc.)
-- This must be done before creating centroids views that include points
SELECT create_points_mview(
    'osm_other_points',
    'mv_other_points'
);


-- ============================================================================
-- Zoom 13-15:
-- ============================================================================
SELECT create_areas_mview(
    'osm_other_areas',
    'mv_other_areas_z13_15',
    5,
    5000,
    'id, osm_id, type',
    NULL
);
SELECT create_points_centroids_mview(
    'mv_other_areas_z13_15',
    'mv_other_points_centroids_z13_15',
    'mv_other_points'
);

-- ============================================================================
-- Zoom 16-20:
-- No simplification
-- All areas
-- Include other points
-- ============================================================================
SELECT create_areas_mview(
    'osm_other_areas',
    'mv_other_areas_z16_20',
    0,
    0,
    'id, osm_id, type',
    NULL
);
SELECT create_points_centroids_mview(
    'mv_other_areas_z16_20',
    'mv_other_points_centroids_z16_20',
    'mv_other_points'
);

/**
layers: other_lines
tegola_config: config/providers/other_lines.toml
filters_per_zoom_level:
- z16-20: mv_other_lines_z16_20 | tolerance=0m | filter=(all)
- z14-15: mv_other_lines_z14_15 | tolerance=5m | filter=(all from parent)

## description:
OpenhistoricalMap other lines, contains miscellaneous linear features that don't fit into specific categories (catch-all layer)

## details:
- Catch-all layer for lines that don't fit into specific categories
**/

-- ============================================================================
-- Create materialized views for other lines
-- ============================================================================
SELECT create_lines_mview('osm_other_lines', 'mv_other_lines_z16_20', 0, 0, 'id, osm_id, type');
SELECT create_mview_line_from_mview('mv_other_lines_z16_20', 'mv_other_lines_z14_15', 5);

-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_areas_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_areas_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_areas_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_areas_z16_20;

-- Refresh centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_points_centroids_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_points_centroids_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_points_centroids_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_points_centroids_z16_20;

-- Refresh lines views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_lines_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_lines_z14_15;

