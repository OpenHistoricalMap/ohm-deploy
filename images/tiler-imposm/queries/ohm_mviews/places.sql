-- ============================================================================
-- Function: create_place_points_centroids_mview
-- Description:
--   Creates a materialized view that merges:
--     - Centroids of polygonal place areas using ST_MaximumInscribedCircle
--     - Place points directly from `osm_place_points`, with NULL for area.
--
--   This provides a unified layer of named place features optimized for
--   rendering at various zoom levels in vector tiles.
--
--   Temporal fields `start_date` and `end_date` are included as-is,
--   and additional precalculated columns `start_decdate` and `end_decdate`
--   are generated using the `isodatetodecimaldate` function.
--
--   Also includes the `capital` tag (if present), full `tags` column,
--   and dynamically generated multilingual name columns from the `languages` table.
--
-- Parameters:
--   view_name            TEXT     - Name of the materialized view to create.
--   allowed_types_areas  TEXT[]   - Optional list of types to include only from `osm_place_areas`.
--   allowed_types_points TEXT[]   - Optional list of types to include only from `osm_place_points`.
--
-- Notes:
--   - Only features with non-empty "name" values are included.
--   - Centroid area is stored in `area_m2` for polygons; NULL for points.
--   - GiST index is created on `geometry`; uniqueness on (osm_id, type).
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
            NULLIF(name, '') AS name,
            type,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
            ROUND(area)::bigint AS area_m2,
            tags->'capital' AS capital,
            %s
        FROM osm_place_areas
        WHERE name IS NOT NULL AND name <> ''%s

        UNION ALL

        SELECT 
            geometry,
            osm_id,
            NULLIF(name, '') AS name,
            type,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
            NULL AS area_m2,
            tags->'capital' AS capital,
            %s
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
--   Creates a materialized view from polygonal place areas in the `osm_place_areas` table.
--   Only features with non-empty "name" values are included, and an optional filter
--   by type allows control over which place types are added to the view.
--
--   The view includes:
--     - Raw geometry of the polygon,
--     - Name and type fields,
--     - Temporal fields `start_date` and `end_date` (as-is),
--     - Precomputed fields `start_decdate` and `end_decdate` using the
--       `isodatetodecimaldate` function for date filtering,
--     - Area in square meters (`area_m2`),
--     - `capital` tag (if available),
--     - Complete `tags` column,
--     - Multilingual name columns dynamically generated from the `languages` table.
--
-- Parameters:
--   view_name            TEXT     - Name of the materialized view to be created.
--   allowed_types_areas  TEXT[]   - Optional list of place types (e.g., 'square', 'islet').
--                                   If NULL or empty, all types are included.
--
-- Notes:
--   - Drops the materialized view if it already exists.
--   - Geometry is indexed using GiST.
--   - Uniqueness is enforced on (osm_id, type).
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
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
            ROUND(ST_Area(geometry))::bigint AS area_m2,
            tags->'capital' AS capital,
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
