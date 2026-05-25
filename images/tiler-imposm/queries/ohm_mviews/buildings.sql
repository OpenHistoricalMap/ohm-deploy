-- ============================================================================
-- Index on building relation outline members.
-- Speeds up the hide_3d EXISTS subquery in mv_buildings_areas_z16_20.
-- ============================================================================
CREATE INDEX IF NOT EXISTS osm_buildings_relation_members_outline_idx
    ON osm_buildings_relation_members (member)
    WHERE role = 'outline';

-- ============================================================================
-- Points mview for zoom 12+. Building and roof attributes come from imposm
-- in osm_buildings_points. Point buildings don't render in 3D, so
-- render_height and render_min_height are NULL placeholders. They're here
-- so the UNION with polygon centroids in mv_buildings_points_centroids_*
-- lines up column-for-column.
-- ============================================================================
SELECT create_points_mview(
    'osm_buildings_points',
    'mv_buildings_points',
    'id, source, osm_id',
    ARRAY[
        'NULL::double precision AS render_height',
        'NULL::double precision AS render_min_height',
        'NULL::double precision AS roof_height',
        'NULL::text AS building_material',
        'NULL::text AS building_colour',
        'NULL::text AS building_part',
        'FALSE::boolean AS is_building_part',
        'FALSE::boolean AS hide_3d',
        'NULL::text AS roof_material',
        'NULL::text AS roof_colour',
        'NULL::text AS roof_shape'
    ],
    NULL
);


-- ============================================================================
-- Base areas mview, zoom 16-20.
-- render_height and render_min_height use the openmaptiles fallback:
-- parsed height first, then building:height (deprecated), then
-- building:levels * 3m. Raw height and level columns are dropped, so
-- anything downstream reads render_height / render_min_height instead.
-- roof_height stays separate (parsed, not combined) since roof rendering
-- needs it on its own. Lower zooms inherit this schema.
-- ============================================================================

SELECT create_areas_mview(
    'osm_buildings',
    'mv_buildings_areas_z16_20',
    0,
    0,
    'id, osm_id, type',
    NULL,
    '(class = ''building:part'') AS is_building_part,
     EXISTS (SELECT 1 FROM osm_buildings_relation_members obrm WHERE obrm.member = ABS(osm_buildings.osm_id) AND obrm.role = ''outline'') AS hide_3d,
     render_height(height, building_height, building_levels) AS render_height,
     render_min_height(min_height, building_min_level) AS render_min_height',
    '{"roof_height": "parse_to_meters(roof_height)"}'::jsonb,
    ARRAY['height', 'min_height', 'building_height', 'building_levels', 'building_min_level']
);

-- ============================================================================
-- Areas z14-15, derived from z16-20.
-- Light 5m simplification, drops buildings under 5,000 m².
-- ============================================================================
SELECT create_area_mview_from_mview(
    'mv_buildings_areas_z16_20',
    'mv_buildings_areas_z14_15',
    5,
    5000,
    NULL
);

-- ============================================================================
-- Centroid mviews per zoom. Each one UNIONs polygon centroids with
-- point-tagged buildings.
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


-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_areas_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_areas_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_points_centroids_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_points_centroids_z16_20;
