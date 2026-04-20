-- ============================================================================
-- Standalone address points (nodes with addr:housenumber that do NOT carry
-- another primary feature tag — buildings, shops, amenities, etc.).
--
-- Features with a primary tag + addr:housenumber already live in their own
-- layer (buildings_points, amenity_points, ...) and should expose the address
-- as a secondary attribute there, not as a duplicate point here.
-- See issue #1304.
-- ============================================================================
SELECT create_points_mview(
    'osm_address_points',
    'mv_address_points',
    'id, source, osm_id',
    NULL,
    NULL
);

-- Refresh:
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_address_points;
