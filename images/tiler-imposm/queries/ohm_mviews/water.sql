/**
layers: water_areas
tegola_config: config/providers/water_areas.toml
filters_per_zoom_level:
- z16-20: mv_water_areas_z16_20 | tolerance=0m | min_area=0 | filter=(all) | source=osm_water_areas
- z13-15: mv_water_areas_z13_15 | tolerance=5m | min_area=0 | filter=(inherited from z16-20) | source=mv_water_areas_z16_20
- z10-12: mv_water_areas_z10_12 | tolerance=20m | min_area=100 | filter=type IN ('water','pond','basin','canal','mill_pond','riverbank') | source=mv_water_areas_z13_15
- z8-9:   mv_water_areas_z8_9   | tolerance=100m | min_area=10000 | filter=(inherited from z10-12) | source=mv_water_areas_z10_12
- z6-7:   mv_water_areas_z6_7   | tolerance=200m | min_area=1000000 | filter=(inherited from z8-9) | source=mv_water_areas_z8_9
- z3-5:   mv_water_areas_z3_5   | tolerance=1000m | min_area=50000000 | filter=(inherited from z6-7) | source=mv_water_areas_z6_7
- z0-2:   mv_water_areas_z0_2   | tolerance=5000m | min_area=100000000 | filter=type IN ('water','riverbank') | source=mv_water_areas_z3_5

## description:
OpenhistoricalMap water areas, contains water body polygons (lakes, ponds, rivers, canals, etc.)
**/

-- ============================================================================
-- Water Areas Materialized Views for Multiple Zoom Levels
-- Creates a pyramid of materialized views for water areas, optimized for
-- ============================================================================

-- Delete existing views, in cascade
DROP MATERIALIZED VIEW IF EXISTS mv_water_areas_z16_20 CASCADE;

SELECT create_areas_mview('osm_water_areas','mv_water_areas_z16_20',0,0,'id, osm_id, type');
SELECT create_area_mview_from_mview('mv_water_areas_z16_20','mv_water_areas_z13_15',5,0.0,NULL);
SELECT create_area_mview_from_mview('mv_water_areas_z13_15','mv_water_areas_z10_12',20,100, 'type IN (''water'',''pond'',''basin'',''canal'',''mill_pond'',''riverbank'')');
SELECT create_area_mview_from_mview('mv_water_areas_z10_12','mv_water_areas_z8_9',100,10000, NULL);
SELECT create_area_mview_from_mview('mv_water_areas_z8_9','mv_water_areas_z6_7',200,1000000, NULL);
SELECT create_area_mview_from_mview('mv_water_areas_z6_7','mv_water_areas_z3_5',1000,50000000, NULL);
SELECT create_area_mview_from_mview('mv_water_areas_z3_5','mv_water_areas_z0_2',5000,100000000, 'type IN (''water'',''riverbank'')');

/**
layers: water_areas_centroids
tegola_config: config/providers/water_areas_centroids.toml
filters_per_zoom_level:
- z16-20: mv_water_areas_centroids_z16_20 | filter=name IS NOT NULL AND name <> ''
- z13-15: mv_water_areas_centroids_z13_15 | filter=name IS NOT NULL AND name <> ''
- z10-12: mv_water_areas_centroids_z10_12 | filter=name IS NOT NULL AND name <> ''
- z8-9:   mv_water_areas_centroids_z8_9   | filter=name IS NOT NULL AND name <> ''

## description:
OpenhistoricalMap water areas centroids, contains point representations of named water bodies (centroids from polygons)

## details:
- Created from water areas using centroids, only for named features
**/

-- ============================================================================
-- Water Areas Centroids Materialized Views for Multiple Zoom Levels
-- ============================================================================
select create_mview_centroid_from_mview('mv_water_areas_z16_20','mv_water_areas_centroids_z16_20', 'name IS NOT NULL AND name <> ''''');
select create_mview_centroid_from_mview('mv_water_areas_z13_15','mv_water_areas_centroids_z13_15', 'name IS NOT NULL AND name <> ''''');
select create_mview_centroid_from_mview('mv_water_areas_z10_12','mv_water_areas_centroids_z10_12', 'name IS NOT NULL AND name <> ''''');
select create_mview_centroid_from_mview('mv_water_areas_z8_9','mv_water_areas_centroids_z8_9', 'name IS NOT NULL AND name <> ''''');


/**
layers: water_lines
tegola_config: config/providers/water_lines.toml
filters_per_zoom_level:
- z16-20: mv_water_lines_z16_20 | tolerance=0m | filter=type IN ('river','canal','cliff','dam','stream','ditch','drain') | source=osm_water_lines
- z13-15: mv_water_lines_z13_15 | tolerance=5m | filter=type IN ('river','canal','cliff','dam','stream') | source=mv_water_lines_z16_20
- z10-12: mv_water_lines_z10_12 | tolerance=20m | filter=type IN ('river','canal','cliff','dam') | source=mv_water_lines_z13_15
- z8-9:   mv_water_lines_z8_9   | tolerance=100m | filter=type IN ('river','canal') | source=mv_water_lines_z10_12

## description:
OpenhistoricalMap water lines, contains linear water features (rivers, canals, streams, ditches, dams, etc.)
**/

-- ============================================================================
-- Water lines Materialized Views for Multiple Zoom Levels
-- ============================================================================

SELECT create_lines_mview('osm_water_lines', 'mv_water_lines_z16_20', 0, 0, 'id, osm_id, type', 'type IN (''river'', ''canal'', ''cliff'', ''dam'', ''stream'', ''ditch'', ''drain'')');
SELECT create_mview_line_from_mview('mv_water_lines_z16_20', 'mv_water_lines_z13_15', 5, 'type IN (''river'', ''canal'', ''cliff'', ''dam'', ''stream'')');
SELECT create_mview_line_from_mview('mv_water_lines_z13_15', 'mv_water_lines_z10_12', 20, 'type IN (''river'', ''canal'', ''cliff'', ''dam'')');
SELECT create_mview_line_from_mview('mv_water_lines_z10_12', 'mv_water_lines_z8_9', 100, 'type IN (''river'', ''canal'')');

-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z3_5;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY  mv_water_areas_z0_2;

-- Refresh centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_areas_centroids_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_areas_centroids_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_areas_centroids_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_areas_centroids_z8_9;

-- Refresh lines views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_lines_z16_20
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_lines_z13_15
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_lines_z10_12
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_water_lines_z8_9