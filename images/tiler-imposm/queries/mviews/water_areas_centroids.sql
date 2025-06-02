-- ============================================================================
-- Function: create_or_refresh_water_areas_centroids_mview
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
-- ============================================================================

DROP FUNCTION IF EXISTS create_or_refresh_water_areas_centroids_mview;
CREATE OR REPLACE FUNCTION create_or_refresh_water_areas_centroids_mview(
    source_table TEXT,
    view_name TEXT,
    force_create BOOLEAN DEFAULT FALSE
)
RETURNS void AS $$
DECLARE 
    sql_drop TEXT;
    sql_create TEXT;
    sql_index TEXT;
    sql_unique_index TEXT;
    lang_columns TEXT;
BEGIN
    -- Check if we should recreate or refresh the view
    IF NOT force_create AND NOT refresh_mview(view_name) THEN
        RETURN;
    END IF;

    RAISE NOTICE 'Creating centroid materialized view from % to %', source_table, view_name;

    -- Get dynamic language columns from `languages` table
    lang_columns := get_language_columns();

    -- Drop existing materialized view
    sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
    EXECUTE sql_drop;
    RAISE NOTICE 'Dropped materialized view: %', view_name;

    -- Create the materialized view with centroid geometry
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            osm_id,
            name,
            type,
            start_date,
            end_date,
            area,
            %s,
            tags,
            (ST_MaximumInscribedCircle(geometry)).center AS geometry
        FROM %I
        WHERE name IS NOT NULL AND name <> '';
    $sql$, view_name, lang_columns, source_table);
    EXECUTE sql_create;
    RAISE NOTICE 'Created materialized view: %', view_name;

    -- Create spatial index
    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;
    RAISE NOTICE 'Created spatial index: idx_%_geom', view_name;

    -- Create unique index on osm_id
    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_osm_id ON %I (osm_id);', view_name, view_name);
    EXECUTE sql_unique_index;
    RAISE NOTICE 'Created unique index: idx_%_osm_id', view_name;

END;
$$ LANGUAGE plpgsql;
SELECT create_or_refresh_water_areas_centroids_mview('osm_water_areas_z0_2', 'mv_water_areas_centroids_z0_2', TRUE);
SELECT create_or_refresh_water_areas_centroids_mview('osm_water_areas_z3_5', 'mv_water_areas_centroids_z3_5', TRUE);
SELECT create_or_refresh_water_areas_centroids_mview('osm_water_areas_z6_7', 'mv_water_areas_centroids_z6_7', TRUE);
SELECT create_or_refresh_water_areas_centroids_mview('osm_water_areas_z8_9', 'mv_water_areas_centroids_z8_9', TRUE);
SELECT create_or_refresh_water_areas_centroids_mview('osm_water_areas_z10_12', 'mv_water_areas_centroids_z10_12', TRUE);
SELECT create_or_refresh_water_areas_centroids_mview('osm_water_areas_z13_15', 'mv_water_areas_centroids_z13_15', TRUE);
