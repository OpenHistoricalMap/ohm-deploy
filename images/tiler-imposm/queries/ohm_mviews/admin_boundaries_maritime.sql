/**
layers: admin_boundaries_maritime
tegola_config: config/providers/admin_boundaries_maritime.toml
filters_per_zoom_level:
- z10-15: mv_admin_maritime_lines_z10_15 | tolerance=10m | filter=maritime = 'yes'
- z6-9:   mv_admin_maritime_lines_z6_9   | tolerance=500m | filter=maritime = 'yes'
- z0-5:   mv_admin_maritime_lines_z0_5_v2 | tolerance=2000m | filter=maritime = 'yes'

## description:
OpenhistoricalMap maritime admin boundaries, contains maritime administrative boundary lines (territorial waters, exclusive economic zones, etc.)

## details:
- Filters boundaries from osm_admin_lines where maritime = 'yes' tag is present
**/

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

-- Refresh maritime lines views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_maritime_lines_z0_5_v2;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_maritime_lines_z6_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_admin_maritime_lines_z10_15;
