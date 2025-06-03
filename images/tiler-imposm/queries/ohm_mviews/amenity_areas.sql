-- Create mv using generic function
SELECT create_or_refresh_generic_mview( 'osm_amenity_areas', 'mv_amenity_areas_z14_20', TRUE, ARRAY['osm_id', 'type']);
