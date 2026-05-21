-- ============================================================================
-- Prepare points materialized view for higher zoom levels (12+)
-- All building/roof attributes (height, building:height, building:material, etc.)
-- are now extracted as native columns by imposm in osm_buildings_points
-- ============================================================================
-- 3D / rendering attributes (height, materials, colours, levels, parts, roof
-- shape) are only meaningful on polygon footprints. Points (building=*
-- nodes) keep just identity/classification fields (name, type, building_use,
-- addresses). Inject NULLs of matching types so the UNION with polygon
-- centroids in mv_buildings_points_centroids_* aligns by name and type.
SELECT create_points_mview(
    'osm_buildings_points',
    'mv_buildings_points',
    'id, source, osm_id',
    ARRAY[
        'NULL::double precision AS height',
        'NULL::double precision AS min_height',
        'NULL::double precision AS roof_height',
        'NULL::numeric AS building_min_level',
        'NULL::text AS building_material',
        'NULL::numeric AS building_levels',
        'NULL::text AS building_colour',
        'NULL::text AS building_part',
        'NULL::text AS roof_material',
        'NULL::text AS roof_colour',
        'NULL::text AS roof_shape'
    ],
    NULL
);



-- ============================================================================
-- Zoom 16-20: BASE
-- No simplification, all areas. Height columns are parsed to numeric here.
-- `height` falls back to deprecated `building:height` and `building_height`
-- is dropped from the output. All derived zoom levels inherit this.
-- ============================================================================
SELECT create_areas_mview(
    'osm_buildings',
    'mv_buildings_areas_z16_20',
    0,
    0,
    'id, osm_id, type',
    NULL,
    NULL,
    '{"height": "COALESCE(parse_to_meters(height), parse_to_meters(building_height))", "min_height": "parse_to_meters(min_height)", "roof_height": "parse_to_meters(roof_height)", "building_levels": "clean_numeric(building_levels)", "building_min_level": "clean_numeric(building_min_level)"}'::jsonb,
    ARRAY['building_height']
);

-- ============================================================================
-- Zoom 14-15: derived from z16_20
-- Low simplification (5m), filters out small buildings (<5,000 m²)
-- ============================================================================
SELECT create_area_mview_from_mview(
    'mv_buildings_areas_z16_20',
    'mv_buildings_areas_z14_15',
    5,
    5000,
    NULL
);

-- ============================================================================
-- Centroids per zoom level (UNION with point-tagged buildings)
-- ============================================================================
SELECT create_points_centroids_mview(
    'mv_buildings_areas_z16_20',
    'mv_buildings_points_centroids_z16_20',
    'mv_buildings_points'
);
SELECT create_points_centroids_mview(
    'mv_buildings_areas_z14_15',
    'mv_buildings_points_centroids_z14_15',
    'mv_buildings_points'
);

-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_areas_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_areas_z16_20;

-- Refresh centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_points_centroids_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_points_centroids_z16_20;
