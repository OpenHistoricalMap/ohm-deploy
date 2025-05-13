-- ============================================================================
-- Function: create_place_points_centroids_mview
-- Description:
--   This function creates a materialized view that combines named centroids 
--   from polygonal place areas and named place points into a unified layer.
--   Centroids are calculated using ST_MaximumInscribedCircle for the area geometries,
--   while place points are included as-is with a NULL value for the area field.
--
-- Parameters:
--   view_name      TEXT    - The name of the materialized view to create.
--   allowed_types  TEXT[]  - An optional array of place types to include (e.g., 'region', 'state').
--                            If empty or NULL, all types will be included.
--
-- Notes:
--   - Only features with a non-empty "name" are included.
--   - The resulting view is useful for rendering simplified place labels
--     at various zoom levels in vector tiles.
--   - Geometry is indexed with GiST; uniqueness is enforced on (osm_id, type).
-- ============================================================================

DROP FUNCTION IF EXISTS create_place_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_place_points_centroids_mview(
    view_name TEXT,
    allowed_types TEXT[] DEFAULT ARRAY[]::TEXT[]
)
RETURNS void AS $$
DECLARE 
    sql TEXT;
    type_filter TEXT := '';
BEGIN
    RAISE NOTICE 'Creating materialized view: % with allowed types: %', view_name, allowed_types;

    -- Construye la cláusula de filtro por tipo si hay tipos permitidos
    IF array_length(allowed_types, 1) IS NOT NULL THEN
        type_filter := format(' AND type = ANY (%L)', allowed_types);
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
            area,
            tags->'capital' AS capital,
            tags
        FROM osm_place_areas
        WHERE name IS NOT NULL AND name <> '' %s

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
        WHERE name IS NOT NULL AND name <> '' %s
    $sql$, view_name, type_filter, type_filter);

    EXECUTE sql;

    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type);', view_name, view_name);
END;
$$ LANGUAGE plpgsql;


-- ZOOM 0–2
SELECT create_place_points_centroids_mview(
  'mview_place_points_centroids_z0_2',
  ARRAY[
    'ocean',
    'sea',
    'archipelago',
    'country',
    'territory',
    'unorganized territory'
  ]
);

-- ZOOM 3–5
SELECT create_place_points_centroids_mview(
  'mview_place_points_centroids_z3_5',
  ARRAY[
    'ocean',
    'sea',
    'archipelago',
    'country',
    'territory',
    'unorganized territory',
    'state',
    'province',
    'region'
  ]
);

-- ZOOM 6–10
SELECT create_place_points_centroids_mview(
  'mview_place_points_centroids_z6_10',
  ARRAY[
    'ocean',
    'sea',
    'archipelago',
    'country',
    'territory',
    'unorganized territory',
    'state',
    'province',
    'region',
    'county',
    'municipality',
    'city',
    'town'
  ]
);

-- ZOOM 11–20 (sin filtro, incluye todos los tipos disponibles con nombre)
SELECT create_place_points_centroids_mview(
  'mview_place_points_centroids_z11_20',
  NULL
);