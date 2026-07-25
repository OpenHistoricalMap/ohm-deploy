-- Create areas materialized views
-- Exclude closed highways from https://github.com/OpenHistoricalMap/issues/issues/1194
-- -- We include aerodrome to start at zoom 10 from https://github.com/OpenHistoricalMap/issues/issues/1083
-- -- From https://github.com/OpenHistoricalMap/issues/issues/1141 add 'apron', 'terminal'
DROP MATERIALIZED VIEW IF EXISTS mv_transport_areas_z16_20 CASCADE;

-- ref is overridden with a coalesce over airport coding schemes so a single
-- field can be used for labeling (faa > iata > icao > ref). See
-- https://github.com/OpenHistoricalMap/issues/issues/... (transport_points_centroids ref)
SELECT create_area_mview(
    source           => 'osm_transport_areas',
    target           => 'mv_transport_areas_z16_20',
    where_filter     => 'NOT (class = ''highway'' AND type IN (''motorway'', ''motorway_link'', ''trunk'', ''trunk_link'', ''primary'', ''primary_link'', ''secondary'', ''secondary_link'', ''tertiary'', ''tertiary_link'', ''unclassified'', ''residential'', ''service'', ''living_street'', ''cycleway'', ''bridleway''))',
    column_overrides => '{"ref": "COALESCE(NULLIF(faa, ''''), NULLIF(iata, ''''), NULLIF(icao, ''''), NULLIF(ref, ''''))"}'::jsonb
);
SELECT derive_area_mview(
    source           => 'mv_transport_areas_z16_20',
    target           => 'mv_transport_areas_z13_15',
    simplify_tol     => 5
);
SELECT derive_area_mview(
    source           => 'mv_transport_areas_z13_15',
    target           => 'mv_transport_areas_z10_12',
    simplify_tol     => 20,
    min_metric       => 100,
    where_filter     => 'type IN (''aerodrome'', ''apron'', ''terminal'')'
);
-- Create points materialized view and centroids views
-- ref is overridden with the same coalesce used in mv_transport_areas_* so the
-- UNION in transport_points_centroids produces a consistent ref across origins
SELECT create_point_mview(
    source           => 'osm_transport_points',
    target           => 'mv_transport_points',
    column_overrides => '{"ref": "COALESCE(NULLIF(faa, ''''), NULLIF(iata, ''''), NULLIF(icao, ''''), NULLIF(ref, ''''))"}'::jsonb
);
SELECT derive_centroid_mview(
    source           => 'mv_transport_areas_z16_20',
    target           => 'mv_transport_points_centroids_z16_20',
    union_source     => 'mv_transport_points',
    only_named       => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_transport_areas_z13_15',
    target           => 'mv_transport_points_centroids_z13_15',
    union_source     => 'mv_transport_points',
    only_named       => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_transport_areas_z10_12',
    target           => 'mv_transport_points_centroids_z10_12',
    only_named       => TRUE
);
-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_areas_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_areas_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_areas_z10_12;

-- Refresh centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_points_centroids_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_points_centroids_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_transport_points_centroids_z16_20;
