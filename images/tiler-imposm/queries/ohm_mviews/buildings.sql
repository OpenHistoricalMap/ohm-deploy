/**
layers: buildings
tegola_config: config/providers/buildings_areas.toml
filters_per_zoom_level:
- z16-20: mv_buildings_areas_z16_20 | tolerance=0m | min_area=0 | filter=(all)
- z14-15: mv_buildings_areas_z14_15 | tolerance=5m | min_area=5000 | filter=(all)

## description:
OpenhistoricalMap buildings areas, contains building footprints as polygons with height information when available

## details:
- Includes height information when available
**/

SELECT create_areas_mview(
    'osm_buildings',
    'mv_buildings_areas_z14_15',
    5,
    5000,
    'id, osm_id, type',
    NULL
);

SELECT create_areas_mview(
    'osm_buildings',
    'mv_buildings_areas_z16_20',
    0,
    0,
    'id, osm_id, type',
    NULL
);





/**
layers: buildings_points_centroids
tegola_config: config/providers/buildings_points_centroids.toml
filters_per_zoom_level:
- z16-20: mv_buildings_points_centroids_z16_20 | filter=(all from parent mv_buildings_areas_z16_20)
- z14-15: mv_buildings_points_centroids_z14_15 | filter=(all from parent mv_buildings_areas_z14_15)

## description:
OpenhistoricalMap buildings points centroids, combines centroids from building polygons with point features representing buildings

## details:
- Points centroids are created from areas and points(objects) for higher zoom levels
- Includes height information when available
- Only features with names are included
**/

SELECT create_points_mview( 'osm_buildings_points', 'mv_buildings_points', 'id, source, osm_id', ARRAY['NULL as height']);

SELECT create_points_centroids_mview(
    'mv_buildings_areas_z14_15',
    'mv_buildings_points_centroids_z14_15',
    'mv_buildings_points'
);

SELECT create_points_centroids_mview(
    'mv_buildings_areas_z16_20',
    'mv_buildings_points_centroids_z16_20',
    'mv_buildings_points'
);



-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_areas_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_areas_z16_20;

-- Refresh centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_points_centroids_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_points_centroids_z16_20;
