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
SELECT create_point_mview(
    source           => 'osm_buildings_points',
    target           => 'mv_buildings_points',
    column_overrides => '{
        "render_height": "NULL::double precision",
        "render_min_height": "NULL::double precision",
        "roof_height": "NULL::double precision",
        "building_material": "NULL::text",
        "building_colour": "NULL::text",
        "building_part": "NULL::text",
        "is_building_part": "FALSE::boolean",
        "hide_3d": "FALSE::boolean",
        "roof_material": "NULL::text",
        "roof_colour": "NULL::text",
        "roof_shape": "NULL::text",
        "golf": "NULLIF(tags->''golf'', '''')"
    }'::jsonb
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

SELECT create_area_mview(
    source           => 'osm_buildings',
    target           => 'mv_buildings_areas_z16_20',
    column_overrides => '{
        "is_building_part": "(class = ''building:part'')",
        "hide_3d": "EXISTS (SELECT 1 FROM osm_buildings_relation_members obrm WHERE obrm.member = ABS(osm_buildings.osm_id) AND obrm.role = ''outline'')",
        "render_height": "render_height(height, building_height, building_levels)",
        "render_min_height": "render_min_height(min_height, building_min_level)",
        "golf": "NULLIF(tags->''golf'', '''')",
        "roof_height": "parse_to_meters(roof_height)"
    }'::jsonb,
    exclude_columns  => ARRAY['height', 'min_height', 'building_height', 'building_levels', 'building_min_level']
);

-- ============================================================================
-- Areas z14-15, derived from z16-20.
-- Light 5m simplification, drops buildings under 5,000 m².
-- ============================================================================
SELECT derive_area_mview(
    source           => 'mv_buildings_areas_z16_20',
    target           => 'mv_buildings_areas_z14_15',
    simplify_tol     => 5,
    min_metric       => 5000
);

-- ============================================================================
-- Centroid mviews per zoom. Each one UNIONs polygon centroids with
-- point-tagged buildings.
-- ============================================================================
SELECT derive_centroid_mview(
    source           => 'mv_buildings_areas_z16_20',
    target           => 'mv_buildings_points_centroids_z16_20',
    union_source     => 'mv_buildings_points',
    require_name     => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_buildings_areas_z14_15',
    target           => 'mv_buildings_points_centroids_z14_15',
    union_source     => 'mv_buildings_points',
    require_name     => TRUE
);


-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_areas_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_areas_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_points_centroids_z14_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buildings_points_centroids_z16_20;
