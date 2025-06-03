-- Create mv using generic function
SELECT create_or_refresh_generic_mview( 'osm_buildings', 'mv_osm_buildings_areas_z14_20', TRUE, ARRAY['osm_id', 'type']);
