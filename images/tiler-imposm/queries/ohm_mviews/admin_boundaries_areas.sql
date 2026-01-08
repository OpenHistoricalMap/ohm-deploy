-- ============================================================================
-- Create materialized views for admin boundaries areas
-- ============================================================================

SELECT create_areas_mview(
    'osm_admin_areas',
    'mv_admin_boundaries_areas_z0_2_v2',
    5000,
    0,
    'id, osm_id, type',
    'admin_level IN (1,2)'
);

SELECT create_areas_mview(
    'osm_admin_areas',
    'mv_admin_boundaries_areas_z3_5',
    1000,
    0,
    'id, osm_id, type',
    'admin_level IN (1,2,3,4)'
);

SELECT create_areas_mview(
    'osm_admin_areas',
    'mv_admin_boundaries_areas_z6_7',
    200,
    0,
    'id, osm_id, type',
    'admin_level IN (1,2,3,4,5,6)'
);

SELECT create_areas_mview(
    'osm_admin_areas',
    'mv_admin_boundaries_areas_z8_9',
    100,
    0,
    'id, osm_id, type',
    'admin_level IN (1,2,3,4,5,6,7,8,9)'
);

SELECT create_areas_mview(
    'osm_admin_areas',
    'mv_admin_boundaries_areas_z10_12',
    20,
    0,
    'id, osm_id, type',
    'admin_level IN (1,2,3,4,5,6,7,8,9,10)'
);

SELECT create_areas_mview(
    'osm_admin_areas',
    'mv_admin_boundaries_areas_z13_15',
    5,
    0,
    'id, osm_id, type',
    'admin_level IN (1,2,3,4,5,6,7,8,9,10,11)'
);

SELECT create_areas_mview(
    'osm_admin_areas',
    'mv_admin_boundaries_areas_z16_20',
    1,
    0,
    'id, osm_id, type',
    'admin_level IN (1,2,3,4,5,6,7,8,9,10,11)'
);
