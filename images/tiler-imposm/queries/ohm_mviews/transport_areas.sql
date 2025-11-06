-- ============================================================================
-- Zoom 10-11:
-- Medium-low simplification (15m)
-- Medium areas (>50K m² = 0.05 km²)
-- We include aerodrome to start at zoom 10 from https://github.com/OpenHistoricalMap/issues/issues/1083
-- From https://github.com/OpenHistoricalMap/issues/issues/1141 add 'apron', 'terminal' 
-- ============================================================================
SELECT create_areas_mview(
    'osm_transport_areas',
    'mv_transport_areas_z10_11',
    15,
    50000,
    'id, osm_id, type',
    'type in (''aerodrome'', ''apron'', ''terminal'')'
);

SELECT create_points_centroids_mview(
    'mv_transport_areas_z10_11',
    'mv_transport_points_centroids_z10_11',
    NULL
);

-- ============================================================================
-- Prepare points materialized view for higher zoom levels (12+)
-- ============================================================================
-- Prepare points table with necessary columns (start_decdate, end_decdate, area_m2, area_km2, etc.)
-- This must be done before creating centroids views that include points
SELECT create_points_mview(
    'osm_transport_points',
    'mv_transport_points'
);

-- ============================================================================
-- Zoom 12-13:
-- Low simplification (10m)
-- Small areas (>10K m² = 0.01 km²)
-- Include other points
-- Exclude closed highways from https://github.com/OpenHistoricalMap/issues/issues/1194
-- ============================================================================
SELECT create_areas_mview(
    'osm_transport_areas',
    'mv_transport_areas_z12_13',
    10,
    10000,
    'id, osm_id, type',
    'NOT (class = ''highway'' AND type IN (''motorway'', ''motorway_link'', ''trunk'', ''trunk_link'', ''primary'', ''primary_link'', ''secondary'', ''secondary_link'', ''tertiary'', ''tertiary_link'', ''unclassified'', ''residential'', ''service'', ''living_street'', ''cycleway'', ''bridleway''))'
);
SELECT create_points_centroids_mview(
    'mv_transport_areas_z12_13',
    'mv_transport_points_centroids_z12_13',
    'mv_transport_points'
);

-- ============================================================================
-- Zoom 14-15:
-- Very low simplification (5m)
-- Very small areas (>5K m² = 0.005 km²)
-- Include transport points
-- Exclude closed highways from https://github.com/OpenHistoricalMap/issues/issues/1194
-- ============================================================================
SELECT create_areas_mview(
    'osm_transport_areas',
    'mv_transport_areas_z14_15',
    5,
    5000,
    'id, osm_id, type',
    'NOT (class = ''highway'' AND type IN (''motorway'', ''motorway_link'', ''trunk'', ''trunk_link'', ''primary'', ''primary_link'', ''secondary'', ''secondary_link'', ''tertiary'', ''tertiary_link'', ''unclassified'', ''residential'', ''service'', ''living_street'', ''cycleway'', ''bridleway''))'
);
SELECT create_points_centroids_mview(
    'mv_transport_areas_z14_15',
    'mv_transport_points_centroids_z14_15',
    'mv_transport_points'
);

-- ============================================================================
-- Zoom 16-20:
-- No simplification
-- All areas
-- Include transport points
-- Exclude closed highways from https://github.com/OpenHistoricalMap/issues/issues/1194

-- ============================================================================
SELECT create_areas_mview(
    'osm_transport_areas',
    'mv_transport_areas_z16_20',
    0,
    0,
    'id, osm_id, type',
    'NOT (class = ''highway'' AND type IN (''motorway'', ''motorway_link'', ''trunk'', ''trunk_link'', ''primary'', ''primary_link'', ''secondary'', ''secondary_link'', ''tertiary'', ''tertiary_link'', ''unclassified'', ''residential'', ''service'', ''living_street'', ''cycleway'', ''bridleway''))'
);
SELECT create_points_centroids_mview(
    'mv_transport_areas_z16_20',
    'mv_transport_points_centroids_z16_20',
    'mv_transport_points'
);
