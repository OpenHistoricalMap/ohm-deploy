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
