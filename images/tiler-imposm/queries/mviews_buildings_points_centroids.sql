-- ============================================================================
-- Function: create_buildings_points_centroids_mview
-- Description:
--   This function creates a materialized view that merges named centroids from
--   polygonal building areas and named building points into a single unified layer 
--   called "buildings_points_centroids".
--
--   For building areas, centroids are calculated using ST_MaximumInscribedCircle, and
--   the area is included in square meters (as integer). If available, height values 
--   are cleaned and cast to double precision.
--
--   Named building points are included directly, with NULL values for both 
--   height and area.
--
-- Parameters:
--   view_name   TEXT             - The name of the materialized view to be created.
--   min_area    DOUBLE PRECISION - Minimum area (in m²) to include building areas.
--
-- Notes:
--   - Only features with a non-empty "name" are included.
--   - Designed to support zoom-level generalization for vector tiles.
--   - Area is stored as integer (m²) to reduce tile size.
--   - Height values are sanitized (non-numeric characters removed).
--   - Geometry is indexed using GiST; uniqueness is enforced on (osm_id, type).
-- ============================================================================

DROP FUNCTION IF EXISTS create_buildings_points_centroids_mview;
CREATE OR REPLACE FUNCTION create_buildings_points_centroids_mview(
    view_name TEXT,
    min_area DOUBLE PRECISION DEFAULT 0
)
RETURNS void AS $$
DECLARE
    sql_drop TEXT;
    sql_create TEXT;
    sql_index TEXT;
    sql_unique_index TEXT;
BEGIN
    RAISE NOTICE 'Dropping materialized view %', view_name;
    sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
    EXECUTE sql_drop;

    RAISE NOTICE 'Creating materialized view % with area > %', view_name, min_area;
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS

        SELECT
            geometry,
            osm_id,
            name,
            NULL AS height,
            NULL AS area_m2,
            type,
            start_date,
            end_date,
            tags
        FROM osm_buildings_points_named
        WHERE name IS NOT NULL AND name <> ''

        UNION ALL

        SELECT
            (ST_MaximumInscribedCircle(geometry)).center AS geometry,
            osm_id,
            name,
            CASE
			  WHEN height IS NULL OR trim(height) = '' THEN NULL
			  ELSE regexp_replace(height, '[^0-9\.]', '', 'g')::double precision
			END AS height,
            ROUND(area)::bigint AS area_m2,
            type,
            start_date,
            end_date,
            tags
        FROM osm_buildings
        WHERE name IS NOT NULL AND name <> '' AND area >= %L

    $sql$, view_name, min_area);
    EXECUTE sql_create;

    RAISE NOTICE 'Creating indexes on %', view_name;
    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_uid ON %I (osm_id, type);', view_name, view_name);
    EXECUTE sql_unique_index;

    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;

    RAISE NOTICE 'Materialized view % created successfully.', view_name;
END;
$$ LANGUAGE plpgsql;


SELECT create_buildings_points_centroids_mview('mview_buildings_points_centroids_z14_20', 0);