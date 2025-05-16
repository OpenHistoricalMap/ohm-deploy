-- ============================================================================
-- Function: create_place_points_centroids_mview
-- Description:
--   This function creates a materialized view that combines named centroids 
--   from polygonal place areas and named place points into a unified layer.
--   Centroids are calculated using ST_MaximumInscribedCircle for area geometries,
--   while place points are included as-is with a NULL value for the area field.
--
-- Parameters:
--   view_name            TEXT     - The name of the materialized view to create.
--   allowed_types_areas  TEXT[]   - Optional array of place types (e.g., 'region', 'state')
--                                   to include **only from** `osm_place_areas`.
--                                   If empty or NULL, all area types are included.
--   allowed_types_points TEXT[]   - Optional array of place types to include **only from**
--                                   `osm_place_points`. If empty or NULL, all point types are included.
--
-- Notes:
--   - Only features with a non-empty "name" are included.
--   - The resulting view is useful for rendering simplified place labels
--     at various zoom levels in vector tiles.
--   - Geometry is indexed with GiST; uniqueness is enforced on (osm_id, type).
--   - This separation allows finer control over which feature types are drawn
--     as centroids vs. raw points.
-- ============================================================================

DROP FUNCTION IF EXISTS create_place_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_place_points_centroids_mview(
    view_name TEXT,
    allowed_types_areas TEXT[] DEFAULT ARRAY[]::TEXT[],
    allowed_types_points TEXT[] DEFAULT ARRAY[]::TEXT[]
)
RETURNS void AS $$
DECLARE 
    sql TEXT;
    type_filter_areas TEXT := '';
    type_filter_points TEXT := '';
BEGIN
    RAISE NOTICE 'Creating materialized view: %', view_name;

    IF array_length(allowed_types_areas, 1) IS NOT NULL THEN
        type_filter_areas := format(' AND type = ANY (%L)', allowed_types_areas);
    END IF;

    IF array_length(allowed_types_points, 1) IS NOT NULL THEN
        type_filter_points := format(' AND type = ANY (%L)', allowed_types_points);
    END IF;
    
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);

    sql := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            (ST_MaximumInscribedCircle(geometry)).center AS geometry,
            osm_id,
            name,
            type,
            start_date,
            end_date,
            ROUND(area)::bigint AS area_m2,
            tags->'capital' AS capital,
            tags
        FROM osm_place_areas
        WHERE name IS NOT NULL AND name <> ''%s

        UNION ALL

        SELECT 
            geometry,
            osm_id,
            name,
            type,
            start_date,
            end_date,
            NULL AS area,
            tags->'capital' AS capital,
            tags
        FROM osm_place_points
        WHERE osm_id > 0 AND name IS NOT NULL AND name <> ''%s
    $sql$, view_name, type_filter_areas, type_filter_points);

    EXECUTE sql;

    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type);', view_name, view_name);
END;
$$ LANGUAGE plpgsql;

SELECT create_place_points_centroids_mview(
  'mview_place_points_centroids_z0_2',
  ARRAY['plot', 'square', 'islet'],
  ARRAY['ocean', 'sea', 'archipelago', 'country', 'territory', 'unorganized territory']
);

SELECT create_place_points_centroids_mview(
  'mview_place_points_centroids_z3_5',
  ARRAY['plot', 'square', 'islet'],
  ARRAY['ocean', 'sea', 'archipelago', 'country', 'territory', 'unorganized territory', 'state', 'province', 'region']
);

SELECT create_place_points_centroids_mview(
  'mview_place_points_centroids_z6_10',
  ARRAY['plot', 'square', 'islet'],
  ARRAY['ocean', 'sea', 'archipelago', 'country', 'territory', 'unorganized territory', 'state', 'province', 'region', 'county', 'municipality', 'city', 'town']
);

SELECT create_place_points_centroids_mview(
  'mview_place_points_centroids_z11_20',
  ARRAY['plot', 'square', 'islet'],
  ARRAY['country', 'state', 'territory', 'city', 'town', 'village', 'suburb', 'locality', 'hamlet', 'islet', 'neighbourhood']
);
