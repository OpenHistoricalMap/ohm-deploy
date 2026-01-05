-- ============================================================================
-- Create materialized views for maritime admin boundaries
-- ============================================================================
SELECT create_lines_mview(
    'osm_admin_lines',
    'mv_admin_maritime_lines_z0_5_v2',
    2000,
    0,
    'id, osm_id, type',
    'maritime = ''yes'''
);


SELECT create_lines_mview(
    'osm_admin_lines',
    'mv_admin_maritime_lines_z6_9',
    500,
    0,
    'id, osm_id, type',
    'maritime = ''yes'''
  );

SELECT create_lines_mview(
    'osm_admin_lines',
    'mv_admin_maritime_lines_z10_15',
    10,
    0,
    'id, osm_id, type',
    'maritime = ''yes'''
  );
  
