/**
layers: landuse_areas
tegola_config: config/providers/landuse_areas.toml
filters_per_zoom_level:
- z16-20: mv_landuse_areas_z16_20 | tolerance=0m | min_area=0 | filter=NOT (type = 'water' AND class = 'natural') | source=osm_landuse_areas
- z13-15: mv_landuse_areas_z13_15 | tolerance=5m | min_area=10000 | filter=(inherited from z16-20) | source=mv_landuse_areas_z16_20
- z10-12: mv_landuse_areas_z10_12 | tolerance=20m | min_area=50000 | filter=(inherited from z13-15) | source=mv_landuse_areas_z13_15
- z8-9:   mv_landuse_areas_z8_9   | tolerance=100m | min_area=1000000 | filter=(inherited from z10-12) | source=mv_landuse_areas_z10_12
- z6-7:   mv_landuse_areas_z6_7   | tolerance=200m | min_area=10000000 | filter=(inherited from z8-9) | source=mv_landuse_areas_z8_9

## description:
OpenhistoricalMap landuse areas, contains land use and land cover polygons (forests, parks, agricultural areas, etc.)

## details:
- Excludes natural=water (see https://github.com/OpenHistoricalMap/issues/issues/1197)
**/

-- ============================================================================
-- Landuse Areas
-- Create  landuse areas materialized views with simplification and filtering
-- Exclude natrual=water https://github.com/OpenHistoricalMap/issues/issues/1197
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS mv_landuse_areas_z16_20 CASCADE;


SELECT create_areas_mview( 'osm_landuse_areas', 'mv_landuse_areas_z16_20', 0, 0, 'id, osm_id, type', 'NOT (type = ''water'' AND class = ''natural'')');
SELECT create_area_mview_from_mview('mv_landuse_areas_z16_20', 'mv_landuse_areas_z13_15', 5, 10000, NULL);
SELECT create_area_mview_from_mview('mv_landuse_areas_z13_15', 'mv_landuse_areas_z10_12', 20, 50000, NULL);
SELECT create_area_mview_from_mview('mv_landuse_areas_z10_12', 'mv_landuse_areas_z8_9', 100, 1000000, NULL);
SELECT create_area_mview_from_mview('mv_landuse_areas_z8_9', 'mv_landuse_areas_z6_7', 200, 10000000, NULL);


/**
layers: landuse_points_centroids
tegola_config: config/providers/landuse_points_centroids.toml
filters_per_zoom_level:
- z16-20: mv_landuse_points_centroids_z16_20 | filter=(includes points from mv_landuse_points)
- z13-15: mv_landuse_points_centroids_z13_15 | filter=(includes points from mv_landuse_points)
- z10-12: mv_landuse_points_centroids_z10_12 | filter=(centroids only, no points)
- z8-9:   mv_landuse_points_centroids_z8_9   | filter=(centroids only, no points)
- z6-7:   mv_landuse_points_centroids_z6_7   | filter=(centroids only, no points)

## description:
OpenhistoricalMap landuse points centroids, contains point representations of land use features (centroids from polygons and point features)

## details:
- Points centroids are created from areas for higher zoom levels
- Includes points from osm_landuse_points for higher zoom levels
- Lower zoom levels show centroids only, no points
**/

-- ============================================================================
-- Landuse centroids
-- Create points materialized view to add laater with centroids
-- Exclude natrual=water https://github.com/OpenHistoricalMap/issues/issues/1197
-- ============================================================================
SELECT create_points_mview('osm_landuse_points','mv_landuse_points' );
-- Create points centroids materialized views, add points  only for higher zoom levels
SELECT create_points_centroids_mview('mv_landuse_areas_z16_20','mv_landuse_points_centroids_z16_20','mv_landuse_points');
SELECT create_points_centroids_mview( 'mv_landuse_areas_z13_15', 'mv_landuse_points_centroids_z13_15', 'mv_landuse_points');
SELECT create_points_centroids_mview( 'mv_landuse_areas_z10_12', 'mv_landuse_points_centroids_z10_12', NULL);
SELECT create_points_centroids_mview( 'mv_landuse_areas_z8_9', 'mv_landuse_points_centroids_z8_9', NULL);
SELECT create_points_centroids_mview( 'mv_landuse_areas_z6_7', 'mv_landuse_points_centroids_z6_7', NULL);


/**
layers: landuse_lines
tegola_config: config/providers/landuse_lines.toml
filters_per_zoom_level:
- z16-20: mv_landuse_lines_z16_20 | tolerance=5m | filter=type IN ('tree_row')
- z14-15: mv_landuse_lines_z14_15 | tolerance=5m | filter=(all from parent)

## description:
OpenhistoricalMap landuse lines, contains linear land use features.

## details:
- Only tree_row  is consider in this layer
**/

-- ============================================================================
-- Landuse lines
-- Create materialized views for landuse lines, 
-- Only tree_row type is used in the map style
-- ============================================================================
SELECT create_lines_mview('osm_landuse_lines', 'mv_landuse_lines_z16_20', 5, 0, 'id, osm_id, type', 'type IN (''tree_row'')');
SELECT create_mview_line_from_mview('mv_landuse_lines_z16_20', 'mv_landuse_lines_z14_15', 5, NULL);
