/**
layers: transport_areas, transport_points_centroids
tegola_config: config/providers/transport_areas.toml, config/providers/transport_points_centroids.toml
filters_per_zoom_level:
- z16-20: mv_transport_areas_z16_20 | tolerance=0m | min_area=0 | filter=NOT (class = 'highway' AND type IN (...))
- z13-15: mv_transport_areas_z13_15 | tolerance=5m | min_area=0 | filter=(all from parent)
- z10-12: mv_transport_areas_z10_12 | tolerance=20m | min_area=100 | filter=type IN ('aerodrome','apron','terminal')

## description:
OpenhistoricalMap transport areas, contains transportation infrastructure areas (airports, terminals, aprons, railway stations, etc.)

## details:
- Excludes closed highways (see https://github.com/OpenHistoricalMap/issues/issues/1194)
- Includes aerodrome, apron, and terminal types (see https://github.com/OpenHistoricalMap/issues/issues/1083, https://github.com/OpenHistoricalMap/issues/issues/1141)
- Points centroids are created from areas and points for higher zoom levels
**/

-- Create areas materialized views
-- Exclude closed highways from https://github.com/OpenHistoricalMap/issues/issues/1194
-- -- We include aerodrome to start at zoom 10 from https://github.com/OpenHistoricalMap/issues/issues/1083
-- -- From https://github.com/OpenHistoricalMap/issues/issues/1141 add 'apron', 'terminal' 
DROP MATERIALIZED VIEW IF EXISTS mv_transport_areas_z16_20 CASCADE;

SELECT create_areas_mview(
    'osm_transport_areas',
    'mv_transport_areas_z16_20',
    0,
    0,
    'id, osm_id, type',
    'NOT (class = ''highway'' AND type IN (''motorway'', ''motorway_link'', ''trunk'', ''trunk_link'', ''primary'', ''primary_link'', ''secondary'', ''secondary_link'', ''tertiary'', ''tertiary_link'', ''unclassified'', ''residential'', ''service'', ''living_street'', ''cycleway'', ''bridleway''))'
);
SELECT create_area_mview_from_mview('mv_transport_areas_z16_20','mv_transport_areas_z13_15',5,0.0,NULL);
SELECT create_area_mview_from_mview('mv_transport_areas_z13_15','mv_transport_areas_z10_12',20,100, 'type IN (''aerodrome'', ''apron'', ''terminal'')');

-- Create points materialized view and centroids views
SELECT create_points_mview('osm_transport_points', 'mv_transport_points');
SELECT create_points_centroids_mview('mv_transport_areas_z16_20', 'mv_transport_points_centroids_z16_20', 'mv_transport_points');
SELECT create_points_centroids_mview('mv_transport_areas_z13_15', 'mv_transport_points_centroids_z13_15', 'mv_transport_points');
SELECT create_points_centroids_mview('mv_transport_areas_z10_12', 'mv_transport_points_centroids_z10_12', NULL);

-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_areas_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_areas_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_areas_z10_12;

-- Refresh centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_points_centroids_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_points_centroids_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_points_centroids_z16_20;
