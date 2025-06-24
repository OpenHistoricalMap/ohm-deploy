-- ============================================================================
-- Function: create_transport_areas_mview
-- Description:
--   Creates a materialized view combining:
--     - Centroids of named transport polygons from the table 'osm_transport_areas'.
--     - Includes multilingual name columns using the helper function get_language_columns().
--     - Allows optional filtering by the 'type' column.
--
-- Parameters:
--   view_name  TEXT                     - Name of the materialized view to be created.
--   types      TEXT[] DEFAULT ARRAY['*'] 
--              - Optional list of values to filter the 'type' column.
--              - If types = ARRAY['*'], no filtering is applied and all types are included.
--              - If types contains one or more values, a SQL filter "type = ANY (...)" is applied.
--
-- Notes:
--   - Drops any existing view using a temporary swap mechanism.
--   - Geometry is calculated as the centroid of the maximum inscribed circle.
--   - Includes spatial (GiST) index on geometry and a unique index on (osm_id, type, class).
--   - Supports temporal filtering via start_date, end_date, and corresponding decimal date fields.
--   - The resulting view is useful for generalization and rendering transport area centroids in vector tiles.
-- ============================================================================
DROP FUNCTION IF EXISTS create_transport_areas_mview;

CREATE OR REPLACE FUNCTION create_transport_areas_mview(
    view_name TEXT,
    types TEXT[] DEFAULT ARRAY['*']
)
RETURNS void AS $$
DECLARE 
    lang_columns TEXT := get_language_columns();
    tmp_view_name TEXT := view_name || '_tmp';
    unique_columns TEXT := 'osm_id, type, class';
    sql_create TEXT;
    type_filter_areas TEXT := 'TRUE';
BEGIN
   
    IF NOT (array_length(types, 1) = 1 AND types[1] = '*') THEN
        type_filter_areas := format('type = ANY (%L)', types);
    END IF;

    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            (ST_MaximumInscribedCircle(geometry)).center AS geometry,
            ABS(osm_id) AS osm_id, 
            NULLIF(name, '') AS name, 
            class, 
            type, 
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
            ROUND(ST_Area(geometry)::numeric)::bigint AS area_m2,
            %s
        FROM osm_transport_areas
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
-- Create materialized views for transport areas
-- ============================================================================
-- We include aerodrome to start at zoom 10 from https://github.com/OpenHistoricalMap/issues/issues/1083
SELECT create_transport_areas_mview('mv_transport_areas_z10_11', ARRAY['aerodrome']);

SELECT create_transport_areas_mview('mv_transport_areas_z12_20', ARRAY['*']);
