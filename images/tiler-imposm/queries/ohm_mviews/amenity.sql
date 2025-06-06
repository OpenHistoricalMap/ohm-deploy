-- ============================================================================
-- Function: create_amenity_points_centroids_mview
-- Description:
--   Creates a materialized view that merges named centroids from
--   polygonal amenity areas and named amenity points into a unified layer
--   called "amenity_points_centroids".
--
--   For amenity areas, centroids are calculated using ST_MaximumInscribedCircle,
--   and area is stored in square meters (as integer). Amenity points are included
--   directly, with NULL values for the area field.
--
--   Temporal fields `start_date` and `end_date` are included as-is, and 
--   additional precalculated columns `start_decdate` and `end_decdate` 
--   are generated using the `isodatetodecimaldate` function.
--
-- Parameters:
--   view_name     TEXT              - Name of the materialized view to create.
--   min_area      DOUBLE PRECISION - Minimum area (in m²) to include amenity areas.
--
-- Notes:
--   - Only features with a non-empty "name" are included.
--   - Geometry is indexed using GiST.
--   - Uniqueness is enforced on the combination of (osm_id, type).
--   - Language-specific name columns are added dynamically from the `languages` table.
-- ============================================================================
DROP FUNCTION IF EXISTS create_amenity_points_centroids_mview;

CREATE OR REPLACE FUNCTION create_amenity_points_centroids_mview(
    view_name TEXT,
    min_area DOUBLE PRECISION DEFAULT 0
)
RETURNS void AS $$
DECLARE 
    sql_drop TEXT;
    sql_create TEXT;
    sql_index TEXT;
    sql_unique_index TEXT;
    lang_columns TEXT;
BEGIN
    RAISE NOTICE 'Recreating materialized view: % with area > %', view_name, min_area;

    -- Get dynamic language columns from `languages` table
    lang_columns := get_language_columns();

    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);

    sql_create := format(
        $sql$ CREATE MATERIALIZED VIEW %I AS
        SELECT (public.ST_MaximumInscribedCircle(geometry)).center AS geometry,
            osm_id,
            NULLIF(name, '') AS name,
            type,
            ROUND(area)::bigint AS area_m2,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            public.isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
            public.isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
            %s
        FROM public.osm_amenity_areas
        WHERE name IS NOT NULL
            AND name <> ''
            AND area > %L
        UNION ALL
        SELECT geometry,
            osm_id,
            NULLIF(name, '') AS name,
            type,
            NULL AS area_m2,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            public.isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
            public.isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
            %s
        FROM public.osm_amenity_points;
    $sql$,
    view_name,
    lang_columns,
    min_area,
    lang_columns
    );
    EXECUTE sql_create;

    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type);', view_name, view_name);

    RAISE NOTICE 'Materialized view % created successfully.', view_name;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- Create materialized view for amenity points centroids
-- ============================================================================
SELECT create_amenity_points_centroids_mview('mv_amenity_points_centroids_z14_20', 0);

-- ============================================================================
-- Create materialized view for amenity areas
-- ============================================================================
SELECT create_generic_mview( 'osm_amenity_areas', 'mv_amenity_areas_z14_20', ARRAY ['osm_id', 'type']);
