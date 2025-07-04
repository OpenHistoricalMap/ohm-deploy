-- ============================================================================
-- Function: create_water_areas_subdivided_mview
-- Description:
--   Creates a materialized view for water areas using ST_Subdivide to simplify
--   complex geometries. The input geometries are validated with ST_MakeValid and
--   dumped using ST_Dump to extract components.
--
--   Multilingual name columns are added dynamically from the `languages` table.
--
-- Parameters:
--   input_table  TEXT  - The source table containing raw geometries.
--   mview_name   TEXT  - The name of the materialized view to be created.
--
-- Behavior:
--   - Uses a temporary view during creation to avoid downtime.
--   - Only valid POLYGON and MULTIPOLYGON geometries are retained.
--   - Adds GiST spatial index on geometry and unique index on (id).
-- ============================================================================
DROP FUNCTION IF EXISTS create_water_areas_subdivided_mview;

CREATE OR REPLACE FUNCTION create_water_areas_subdivided_mview(
  input_table TEXT,
  mview_name TEXT
)
RETURNS void AS $$
DECLARE
    lang_columns TEXT := get_language_columns();
    tmp_view_name TEXT := mview_name || '_tmp';
    sql_create TEXT;
    unique_columns TEXT := 'id';
BEGIN
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            row_number() OVER () AS id,
            geometry,
            osm_id,
            NULLIF(name, '') AS name,
            NULLIF(type, '') AS type,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
            area,
            %s
        FROM (
            SELECT
                ST_Subdivide((g).geom, 512) AS geometry,
                osm_id,
                name,
                type,
                start_date,
                end_date,
                area,
                tags,
                %s
            FROM (
                SELECT 
                    osm_id,
                    name,
                    type,
                    start_date,
                    end_date,
                    area,
                    ST_Dump(ST_MakeValid(geometry)) AS g,
                    tags,
                    %s
                FROM %I
                WHERE geometry IS NOT NULL
            ) AS fixed_geoms
            WHERE GeometryType((g).geom) IN ('POLYGON', 'MULTIPOLYGON')
        ) AS final_data;
    $sql$, tmp_view_name, lang_columns, lang_columns, lang_columns, input_table);

    PERFORM finalize_materialized_view(
        tmp_view_name,
        mview_name,
        unique_columns,
        sql_create
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Function: create_water_areas_centroids_mview
-- Description:
--   This function creates a materialized view with centroids for named water areas.
--   It uses ST_MaximumInscribedCircle to compute a representative centroid from
--   each polygonal feature. The function can be called per zoom level using different source tables.
--
-- Parameters:
--   source_table TEXT - Source table containing water area polygons.
--   view_name    TEXT - Name of the resulting materialized view.
--
-- Notes:
--   - Only features with non-empty names are included.
--   - Geometry is computed as the center of the maximum inscribed circle.
--   - A GiST index is created on geometry, and uniqueness is enforced on osm_id.
--   - Uses a temporary view to avoid downtime during refresh.
-- ============================================================================

DROP FUNCTION IF EXISTS create_water_areas_centroids_mview;

CREATE OR REPLACE FUNCTION create_water_areas_centroids_mview(
    source_table TEXT,
    view_name TEXT
)
RETURNS void AS $$
DECLARE 
    lang_columns TEXT := get_language_columns();
    tmp_view_name TEXT := view_name || '_tmp';
    sql_create TEXT;
    unique_columns TEXT := 'osm_id, type';
BEGIN
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            osm_id,
            NULLIF(name, '') AS name,
            NULLIF(type, '') AS type,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
            isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
            area,
            %s,
            (ST_MaximumInscribedCircle(geometry)).center AS geometry
        FROM %I
        WHERE name IS NOT NULL AND name <> '';
    $sql$, tmp_view_name, lang_columns, source_table);

    PERFORM finalize_materialized_view(
        tmp_view_name,
        view_name,
        unique_columns,
        sql_create
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Create materialized views for water ceontroids
-- ============================================================================
SELECT create_water_areas_centroids_mview('osm_water_areas_z0_2', 'mv_water_areas_centroids_z0_2');
SELECT create_water_areas_centroids_mview('osm_water_areas_z3_5', 'mv_water_areas_centroids_z3_5');
SELECT create_water_areas_centroids_mview('osm_water_areas_z6_7', 'mv_water_areas_centroids_z6_7');
SELECT create_water_areas_centroids_mview('osm_water_areas_z8_9', 'mv_water_areas_centroids_z8_9');
SELECT create_water_areas_centroids_mview('osm_water_areas_z10_12', 'mv_water_areas_centroids_z10_12');
SELECT create_water_areas_centroids_mview('osm_water_areas_z13_15', 'mv_water_areas_centroids_z13_20');

-- ============================================================================
-- Create materialized views for water areas using subdivided geometries and generic function
-- ============================================================================
SELECT create_water_areas_subdivided_mview('osm_water_areas_z0_2', 'mv_water_areas_z0_2_subdivided');
SELECT create_water_areas_subdivided_mview('osm_water_areas_z3_5', 'mv_water_areas_z3_5_subdivided');
SELECT create_water_areas_subdivided_mview('osm_water_areas_z6_7', 'mv_water_areas_z6_7_subdivided');
SELECT create_water_areas_subdivided_mview('osm_water_areas_z8_9', 'mv_water_areas_z8_9_subdivided');
SELECT create_generic_mview('osm_water_areas_z10_12', 'mv_water_areas_z10_12', ARRAY['osm_id', 'type']);
SELECT create_generic_mview('osm_water_areas_z13_15', 'mv_water_areas_z13_15', ARRAY['osm_id', 'type']);
SELECT create_generic_mview('osm_water_areas', 'mv_water_areas_z16_20', ARRAY['osm_id', 'type']);

-- ============================================================================
-- Create materialized views for water lines
-- ============================================================================
SELECT create_generic_mview('osm_water_lines_z8_9', 'mv_water_lines_z8_9');
SELECT create_generic_mview('osm_water_lines_z10_12', 'mv_water_lines_z10_12');
SELECT create_generic_mview('osm_water_lines_z13_15', 'mv_water_lines_z13_15');
SELECT create_generic_mview('osm_water_lines_z16_20', 'mv_water_lines_z16_20');
