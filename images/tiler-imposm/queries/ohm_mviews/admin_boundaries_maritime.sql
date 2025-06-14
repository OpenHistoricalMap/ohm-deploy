-- ============================================================================
-- Create materialized views for maritime admin boundaries
-- ============================================================================
SELECT create_generic_mview(
    'osm_admin_lines_z0_5',
    'mv_admin_maritime_lines_z0_5',
    ARRAY ['osm_id', 'type']
  );

SELECT create_generic_mview(
    'osm_admin_lines_z6_9',
    'mv_admin_maritime_lines_z6_9',
    ARRAY ['osm_id', 'type']
  );

SELECT create_generic_mview(
    'osm_admin_lines_z10_15',
    'mv_admin_maritime_lines_z10_15',
    ARRAY ['osm_id', 'type']
  );
  