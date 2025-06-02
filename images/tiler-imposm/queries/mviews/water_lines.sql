-- Create mv using generic function
SELECT create_or_refresh_generic_mview('osm_water_lines_z8_9', 'mv_water_lines_z8_9', TRUE);
SELECT create_or_refresh_generic_mview('osm_water_lines_z10_12', 'mv_water_lines_z10_12', TRUE);
SELECT create_or_refresh_generic_mview('osm_water_lines_z13_15', 'mv_water_lines_z13_15', TRUE);
SELECT create_or_refresh_generic_mview('osm_water_lines_z16_20', 'mv_water_lines_z16_20', TRUE);
