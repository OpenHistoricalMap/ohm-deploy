-- ============================================================================
-- Function: create_or_refresh_place_areas_mview
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
--   force_create         BOOLEAN  - If TRUE, forces creation even if data has not changed.
--
-- Behavior:
--   - Drops the materialized view if it exists.
--   - Filters by `type` only if `allowed_types_areas` is provided.
--   - Computes the area using ST_Area and rounds it to the nearest integer.
--   - Adds GiST index on geometry and a unique index on (osm_id, type).
-- ============================================================================

DROP FUNCTION IF EXISTS create_or_refresh_place_areas_mview;
CREATE OR REPLACE FUNCTION create_or_refresh_place_areas_mview(
    view_name TEXT,
    allowed_types_areas TEXT[] DEFAULT NULL,
    force_create BOOLEAN DEFAULT FALSE
)
RETURNS void AS $$
DECLARE 
    sql TEXT;
    type_filter_areas TEXT := 'TRUE';  -- Default WHERE clause
    lang_columns TEXT;
BEGIN
    -- Check if we should recreate or refresh the view
    IF NOT force_create AND NOT refresh_mview(view_name) THEN
        RETURN;
    END IF;

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

SELECT create_or_refresh_place_areas_mview(
  'mv_place_areas_z14_20',
  ARRAY['plot', 'square', 'islet']
);
