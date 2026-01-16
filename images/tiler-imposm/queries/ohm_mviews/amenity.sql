/**
layers: amenity_areas
tegola_config: config/providers/amenity_areas.toml
filters_per_zoom_level:
- z16-20: mv_amenity_areas_z16_20 | tolerance=0m | min_area=0 | filter=(all) | source=osm_amenity_areas
- z14-15: mv_amenity_areas_z14_15 | tolerance=5m | min_area=5000 | filter=(inherited from z16-20) | source=mv_amenity_areas_z16_20

## description:
OpenhistoricalMap amenity areas, contains amenity features as polygons (shops, restaurants, schools, hospitals, etc.)

**/

SELECT create_areas_mview('osm_amenity_areas', 'mv_amenity_areas_z16_20', 0, 0, 'id, osm_id, type', NULL);
SELECT create_area_mview_from_mview( 'mv_amenity_areas_z16_20', 'mv_amenity_areas_z14_15', 5, 5000, NULL);

/**
layers: amenity_points_centroids
tegola_config: config/providers/amenity_points_centroids.toml
filters_per_zoom_level:
- z16-20: mv_amenity_points_centroids_z16_20 | filter=Name IS NOT NULL AND Name <> '' | source=mv_amenity_areas_z16_20
- z14-15: mv_amenity_points_centroids_z14_15 | filter=Name IS NOT NULL AND Name <> '' | source=mv_amenity_areas_z14_15

## description:
OpenhistoricalMap amenity points centroids, combines centroids from amenity polygons with point features representing amenities

## details:
- Combines centroids from amenity areas with points from osm_amenity_points
- Only includes features with names
**/

SELECT create_points_mview( 'osm_amenity_points', 'mv_amenity_points');
SELECT create_points_centroids_mview( 'mv_amenity_areas_z14_15', 'mv_amenity_points_centroids_z14_15', 'mv_amenity_points');
SELECT create_points_centroids_mview( 'mv_amenity_areas_z16_20', 'mv_amenity_points_centroids_z16_20', 'mv_amenity_points');

-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_amenity_areas_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_amenity_areas_z16_20;

-- Refresh centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_amenity_points_centroids_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_amenity_points_centroids_z16_20;
