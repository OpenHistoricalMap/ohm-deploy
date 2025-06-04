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
    lang_columns TEXT;
BEGIN
    RAISE NOTICE 'Creating or refreshing view: %', view_name;

    -- Get dynamic language columns
    lang_columns := get_language_columns();

    -- Apply filters for allowed types
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
            %s,
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
            NULL AS area_m2,
            tags->'capital' AS capital,
            %s,
            tags
        FROM osm_place_points
        WHERE osm_id > 0 AND name IS NOT NULL AND name <> ''%s
    $sql$, view_name, lang_columns, type_filter_areas, lang_columns, type_filter_points);

    EXECUTE sql;

    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type);', view_name, view_name);
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- Function: create_place_areas_mview
-- Description:
--   Creates a materialized view from polygonal place areas in the table 
--   `osm_place_areas`. The function filters by allowed place types.
--
--   The output includes geometry, name, type, start/end date, area in m², 
--   capital tag, all tags, and dynamic language columns.
--
-- Parameters:
--   view_name            TEXT     - The name of the materialized view to be created.
--   allowed_types_areas  TEXT[]   - Optional array of place types (e.g., 'square', 'islet').
--                                   If NULL, all types are included.
--
-- Behavior:
--   - Drops the materialized view if it exists.
--   - Filters by `type` only if `allowed_types_areas` is provided.
--   - Computes the area using ST_Area and rounds it to the nearest integer.
--   - Adds GiST index on geometry and a unique index on (osm_id, type).
-- ============================================================================

DROP FUNCTION IF EXISTS create_place_areas_mview;
CREATE OR REPLACE FUNCTION create_place_areas_mview(
    view_name TEXT,
    allowed_types_areas TEXT[] DEFAULT NULL
)
RETURNS void AS $$
DECLARE 
    sql TEXT;
    type_filter_areas TEXT := 'TRUE';
    lang_columns TEXT;
BEGIN
    RAISE NOTICE 'Creating or refreshing view: %', view_name;

    -- Get dynamic language columns
    lang_columns := get_language_columns();

    -- Prepare filtering condition
    IF array_length(allowed_types_areas, 1) IS NOT NULL THEN
        type_filter_areas := format('type = ANY (%L)', allowed_types_areas);
    END IF;

    -- Drop existing materialized view
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);

    -- Create materialized view with dynamic language columns
    sql := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            geometry,
            osm_id,
            NULLIF(name, '') AS name,
            type,
            start_date,
            end_date,
            ROUND(ST_Area(geometry))::bigint AS area_m2,
            tags->'capital' AS capital,
            tags,
            %s
        FROM osm_place_areas
        WHERE %s;
    $sql$, view_name, lang_columns, type_filter_areas);

    EXECUTE sql;

    -- Create spatial and unique indexes
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type);', view_name, view_name);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Create materialized views for place points centroids
-- ============================================================================
SELECT create_place_points_centroids_mview(
  'mv_place_points_centroids_z0_2',
  ARRAY['plot', 'square', 'islet'],
  ARRAY['ocean', 'sea', 'archipelago', 'country', 'territory', 'unorganized territory']
);

SELECT create_place_points_centroids_mview(
  'mv_place_points_centroids_z3_5',
  ARRAY['plot', 'square', 'islet'],
  ARRAY['ocean', 'sea', 'archipelago', 'country', 'territory', 'unorganized territory', 'state', 'province', 'region']
);

SELECT create_place_points_centroids_mview(
  'mv_place_points_centroids_z6_10',
  ARRAY['plot', 'square', 'islet'],
  ARRAY['ocean', 'sea', 'archipelago', 'country', 'territory', 'unorganized territory', 'state', 'province', 'region', 'county', 'municipality', 'city', 'town']
);

SELECT create_place_points_centroids_mview(
  'mv_place_points_centroids_z11_20',
  ARRAY['plot', 'square', 'islet'],
  ARRAY['country', 'state', 'territory', 'city', 'town', 'village', 'suburb', 'locality', 'hamlet', 'islet', 'neighbourhood']
);


-- ============================================================================
-- Create materialized views for place areas
-- ============================================================================
SELECT create_place_areas_mview(
  'mv_place_areas_z14_20',
  ARRAY['plot', 'square', 'islet']
);
