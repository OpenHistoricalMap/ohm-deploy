-- Create mv using generic function
SELECT create_or_refresh_generic_mview('osm_transport_areas', 'mv_transport_areas_z12_20', TRUE, ARRAY['osm_id', 'type']);
