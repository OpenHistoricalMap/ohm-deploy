-- Create mv using generic function
SELECT create_or_refresh_generic_mview('osm_admin_lines_z0_5', 'mv_admin_maritime_lines_z0_5', TRUE);
SELECT create_or_refresh_generic_mview('osm_admin_lines_z6_9', 'mv_admin_maritime_lines_z6_9', TRUE);
SELECT create_or_refresh_generic_mview('osm_admin_lines_z10_15', 'mv_admin_maritime_lines_z10_15', TRUE);
