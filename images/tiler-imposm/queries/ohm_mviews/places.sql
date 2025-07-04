-- ============================================================================
-- Function: create_place_points_centroids_mview
-- Description:
--   Creates a materialized view that merges place polygons and points into
--   a unified layer of named geographic features optimized for vector tile rendering.
--
--   Includes:
--     - Centroids of polygonal areas (from `osm_place_areas`) calculated using
--       ST_MaximumInscribedCircle, with area in m² stored in `area_m2`.
--     - Direct points (from `osm_place_points`) with NULL for `area_m2`.
--
--   Both sources include:
--     - Name (only non-empty)
--     - Temporal fields: `start_date`, `end_date`
--     - Derived decimal dates: `start_decdate`, `end_decdate` using isodatetodecimaldate()
--     - Capital tag (`tags->'capital'`)
--     - Full `tags` column
--     - Language-specific name columns dynamically from the `languages` table
--
-- Parameters:
--   view_name             TEXT     - Name of the materialized view to create.
--   allowed_types_areas   TEXT[]   - Optional filter for types from `osm_place_areas`.
--   allowed_types_points  TEXT[]   - Optional filter for types from `osm_place_points`.
--
-- Notes:
--   - Features without a name are excluded.
--   - If the array for area or point types is empty, that part is skipped.
--   - Use '*' as wildcard to include all types.
--   - A temporary view is created and replaced atomically using finalize_materialized_view().
--   - Uniqueness is enforced on (osm_id, type), and GiST index is added on geometry.
-- ============================================================================

DROP FUNCTION IF EXISTS create_place_points_centroids_mview;

CREATE OR REPLACE FUNCTION create_place_points_centroids_mview(
  view_name TEXT,
  allowed_types_areas TEXT[] DEFAULT ARRAY[]::TEXT[],
  allowed_types_points TEXT[] DEFAULT ARRAY[]::TEXT[]
)
RETURNS void AS $$
DECLARE 
  lang_columns TEXT := get_language_columns();
  tmp_view_name TEXT := view_name || '_tmp';
  sql_create TEXT;
  type_filter_areas TEXT := '';
  type_filter_points TEXT := '';
  unique_columns TEXT := 'osm_id, type';
BEGIN
  IF array_length(allowed_types_areas, 1) IS NOT NULL THEN
    type_filter_areas := format(' AND type = ANY (%L)', allowed_types_areas);
  END IF;

  IF array_length(allowed_types_points, 1) IS NOT NULL THEN
    type_filter_points := format(' type = ANY (%L)', allowed_types_points);
  END IF;

  sql_create := format($sql$
    CREATE MATERIALIZED VIEW %I AS
    SELECT
      (ST_MaximumInscribedCircle(geometry)).center AS geometry,
      osm_id,
      NULLIF(name, '') AS name,
      type,
      NULLIF(start_date, '') AS start_date,
      NULLIF(end_date, '') AS end_date,
      isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
      isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
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
      isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
      isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
      NULL AS area_m2,
      tags->'capital' AS capital,
      %s
    FROM osm_place_points
    WHERE %s;
  $sql$, tmp_view_name, lang_columns, type_filter_areas, lang_columns, type_filter_points);

  PERFORM finalize_materialized_view(
    tmp_view_name,
    view_name,
    unique_columns,
    sql_create
  );
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
--   - Geometry is indexed using GiST.
--   - Uniqueness is enforced on (osm_id, type).
--   - Uses finalize_materialized_view() for atomic operation.
-- ============================================================================

DROP FUNCTION IF EXISTS create_place_areas_mview;

CREATE OR REPLACE FUNCTION create_place_areas_mview(
    view_name TEXT,
    allowed_types_areas TEXT[] DEFAULT NULL
)
RETURNS void AS $$
DECLARE 
    tmp_view_name TEXT := view_name || '_tmp';
    lang_columns TEXT := get_language_columns();
    type_filter_areas TEXT := 'TRUE';
    sql_create TEXT;
    unique_columns TEXT := 'osm_id, type';
BEGIN
    IF array_length(allowed_types_areas, 1) IS NOT NULL THEN
        type_filter_areas := format('type = ANY (%L)', allowed_types_areas);
    END IF;

    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            geometry,
            osm_id,
            NULLIF(name, '') AS name,
            type,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
            ROUND(ST_Area(geometry))::bigint AS area_m2,
            tags->'capital' AS capital,
            %s
        FROM osm_place_areas
        WHERE %s;
    $sql$, tmp_view_name, lang_columns, type_filter_areas);

    PERFORM finalize_materialized_view(
        tmp_view_name,
        view_name,
        unique_columns,
        sql_create
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Create materialized views for place points centroids
-- ============================================================================
SELECT create_place_points_centroids_mview (
    'mv_place_points_centroids_z0_2',
    ARRAY ['island'],
    ARRAY ['ocean', 'sea', 'archipelago', 'country', 'territory', 'unorganized territory']
  );

SELECT create_place_points_centroids_mview (
    'mv_place_points_centroids_z3_5',
    ARRAY ['island'],
    ARRAY ['ocean', 'sea', 'archipelago', 'country', 'territory', 'unorganized territory', 'state', 'province', 'region']
  );

SELECT create_place_points_centroids_mview (
    'mv_place_points_centroids_z6_10',
    ARRAY ['island'],
    ARRAY ['ocean', 'sea', 'archipelago', 'country', 'territory', 'unorganized territory', 'state', 'province', 'region', 'county', 'municipality', 'city', 'town']
  );

SELECT create_place_points_centroids_mview (
    'mv_place_points_centroids_z11_20',
    ARRAY ['plot', 'square', 'islet'],
    ARRAY ['state', 'province', 'region', 'county', 'municipality', 'city', 'town', 'village', 'suburb', 'locality', 'hamlet', 'islet', 'neighbourhood', 'district', 'borough', 'quarter', 'isolated_dwelling', 'farm']
  );

-- ============================================================================
-- Create materialized views for place areas
-- ============================================================================
SELECT create_place_areas_mview(
  'mv_place_areas_z14_20',
  ARRAY['plot', 'square', 'islet']
);
