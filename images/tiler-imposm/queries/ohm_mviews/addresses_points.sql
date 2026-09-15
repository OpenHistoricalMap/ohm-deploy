-- ============================================================================
-- Standalone address points (nodes with addr:housenumber that do NOT carry
-- another primary feature tag — buildings, shops, amenities, etc.).
--
-- Features with a primary tag + addr:housenumber already live in their own
-- layer (buildings_points, amenity_points, ...) and should expose the address
-- as a secondary attribute there, not as a duplicate point here.
-- See issue #1304.
-- ============================================================================
SELECT create_point_mview(
    source           => 'osm_address_points',
    target           => 'mv_address_points_z16_20',
    unique_columns   => ARRAY['id', 'osm_id']
);

-- Refresh:
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_address_points_z16_20;
