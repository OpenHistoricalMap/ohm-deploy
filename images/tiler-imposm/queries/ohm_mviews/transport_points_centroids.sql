-- ============================================================================
-- Prepare points materialized view for higher zoom levels (12+)
-- ============================================================================
-- Prepare points table with necessary columns (start_decdate, end_decdate, area_m2, area_km2, etc.)
-- This must be done before creating centroids views that include points

SELECT create_points_mview('osm_transport_points', 'mv_transport_points');

-- ============================================================================
-- Create materialized views for transport points centroids
-- ============================================================================
-- We include aerodrome to start at zoom 10 from https://github.com/OpenHistoricalMap/issues/issues/1083
SELECT create_points_centroids_mview('mv_transport_areas_z10_11', 'mv_transport_points_centroids_z10_11', NULL);
SELECT create_points_centroids_mview('mv_transport_areas_z12_20', 'mv_transport_points_centroids_z12_20', 'mv_transport_points');

