-- ============================================================================
-- FUNCTION: create_mv_routes_by_length
-- ============================================================================
-- Purpose:
--   Creates a materialized view with optionally simplified geometry,
--   based on the source view mv_routes_indexed.
--
--   Includes all route_* columns generated in mv_routes_indexed
--   (up to 6 slots per type: road, train, subway, light_rail, tram, trolleybus, bus),
--   applying NULLIF(..., '') to avoid empty string values.
--
--   Automatically creates:
--     - Unique index on (osm_id, start_decdate, end_decdate)
--     - Spatial GIST index on the geometry column
--
-- Parameters:
--   full_view_name TEXT         - Name of the new materialized view
--   simplify_tol DOUBLE PRECISION - Simplification tolerance (ST_Simplify)
--
-- Typical usage:
--   SELECT create_mv_routes_by_length('mv_routes_indexed_z5_6', 500);
--   SELECT create_mv_routes_by_length('mv_routes_indexed_z11_13', 50);
--
-- Notes:
--   - mv_routes_indexed must exist before calling this function.
--   - This function drops the view if it already exists (DROP ... CASCADE).
--   - No LIMIT or dynamic introspection is used: all columns are explicitly listed.
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS create_mv_routes_by_length CASCADE;

CREATE OR REPLACE FUNCTION create_mv_routes_by_length(
    full_view_name TEXT,
    simplify_tol DOUBLE PRECISION
) RETURNS void AS $$
DECLARE
  sql text;
BEGIN
  sql := format($f$
    DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;

    CREATE MATERIALIZED VIEW %I AS
    SELECT
      way_id AS osm_id,
      min_start_decdate AS start_decdate,
      max_end_decdate AS end_decdate,
      min_start_date_iso AS start_date,
      max_end_date_iso AS end_date,
      CASE
        WHEN %s > 0 THEN ST_Simplify(geometry, %s)
        ELSE geometry
      END AS geometry,
      NULLIF(route_road_1_ref, '') AS route_road_1_ref,
      NULLIF(route_road_1_network, '') AS route_road_1_network,
      NULLIF(route_road_1_network_wikidata, '') AS route_road_1_network_wikidata,
      NULLIF(route_road_1_operator, '') AS route_road_1_operator,
      NULLIF(route_road_1_name, '') AS route_road_1_name,
      NULLIF(route_road_1_direction, '') AS route_road_1_direction,

      NULLIF(route_road_2_ref, '') AS route_road_2_ref,
      NULLIF(route_road_2_network, '') AS route_road_2_network,
      NULLIF(route_road_2_network_wikidata, '') AS route_road_2_network_wikidata,
      NULLIF(route_road_2_operator, '') AS route_road_2_operator,
      NULLIF(route_road_2_name, '') AS route_road_2_name,
      NULLIF(route_road_2_direction, '') AS route_road_2_direction,

      NULLIF(route_road_3_ref, '') AS route_road_3_ref,
      NULLIF(route_road_3_network, '') AS route_road_3_network,
      NULLIF(route_road_3_network_wikidata, '') AS route_road_3_network_wikidata,
      NULLIF(route_road_3_operator, '') AS route_road_3_operator,
      NULLIF(route_road_3_name, '') AS route_road_3_name,
      NULLIF(route_road_3_direction, '') AS route_road_3_direction,

      NULLIF(route_road_4_ref, '') AS route_road_4_ref,
      NULLIF(route_road_4_network, '') AS route_road_4_network,
      NULLIF(route_road_4_network_wikidata, '') AS route_road_4_network_wikidata,
      NULLIF(route_road_4_operator, '') AS route_road_4_operator,
      NULLIF(route_road_4_name, '') AS route_road_4_name,
      NULLIF(route_road_4_direction, '') AS route_road_4_direction,

      NULLIF(route_road_5_ref, '') AS route_road_5_ref,
      NULLIF(route_road_5_network, '') AS route_road_5_network,
      NULLIF(route_road_5_network_wikidata, '') AS route_road_5_network_wikidata,
      NULLIF(route_road_5_operator, '') AS route_road_5_operator,
      NULLIF(route_road_5_name, '') AS route_road_5_name,
      NULLIF(route_road_5_direction, '') AS route_road_5_direction,

      NULLIF(route_road_6_ref, '') AS route_road_6_ref,
      NULLIF(route_road_6_network, '') AS route_road_6_network,
      NULLIF(route_road_6_network_wikidata, '') AS route_road_6_network_wikidata,
      NULLIF(route_road_6_operator, '') AS route_road_6_operator,
      NULLIF(route_road_6_name, '') AS route_road_6_name,
      NULLIF(route_road_6_direction, '') AS route_road_6_direction,

      -- =========================================================================
      -- TRAIN
      -- =========================================================================
      NULLIF(route_train_1_ref, '') AS route_train_1_ref,
      NULLIF(route_train_1_network, '') AS route_train_1_network,
      NULLIF(route_train_1_network_wikidata, '') AS route_train_1_network_wikidata,
      NULLIF(route_train_1_operator, '') AS route_train_1_operator,
      NULLIF(route_train_1_name, '') AS route_train_1_name,
      NULLIF(route_train_1_direction, '') AS route_train_1_direction,

      NULLIF(route_train_2_ref, '') AS route_train_2_ref,
      NULLIF(route_train_2_network, '') AS route_train_2_network,
      NULLIF(route_train_2_network_wikidata, '') AS route_train_2_network_wikidata,
      NULLIF(route_train_2_operator, '') AS route_train_2_operator,
      NULLIF(route_train_2_name, '') AS route_train_2_name,
      NULLIF(route_train_2_direction, '') AS route_train_2_direction,

      NULLIF(route_train_3_ref, '') AS route_train_3_ref,
      NULLIF(route_train_3_network, '') AS route_train_3_network,
      NULLIF(route_train_3_network_wikidata, '') AS route_train_3_network_wikidata,
      NULLIF(route_train_3_operator, '') AS route_train_3_operator,
      NULLIF(route_train_3_name, '') AS route_train_3_name,
      NULLIF(route_train_3_direction, '') AS route_train_3_direction,

      NULLIF(route_train_4_ref, '') AS route_train_4_ref,
      NULLIF(route_train_4_network, '') AS route_train_4_network,
      NULLIF(route_train_4_network_wikidata, '') AS route_train_4_network_wikidata,
      NULLIF(route_train_4_operator, '') AS route_train_4_operator,
      NULLIF(route_train_4_name, '') AS route_train_4_name,
      NULLIF(route_train_4_direction, '') AS route_train_4_direction,

      NULLIF(route_train_5_ref, '') AS route_train_5_ref,
      NULLIF(route_train_5_network, '') AS route_train_5_network,
      NULLIF(route_train_5_network_wikidata, '') AS route_train_5_network_wikidata,
      NULLIF(route_train_5_operator, '') AS route_train_5_operator,
      NULLIF(route_train_5_name, '') AS route_train_5_name,
      NULLIF(route_train_5_direction, '') AS route_train_5_direction,

      NULLIF(route_train_6_ref, '') AS route_train_6_ref,
      NULLIF(route_train_6_network, '') AS route_train_6_network,
      NULLIF(route_train_6_network_wikidata, '') AS route_train_6_network_wikidata,
      NULLIF(route_train_6_operator, '') AS route_train_6_operator,
      NULLIF(route_train_6_name, '') AS route_train_6_name,
      NULLIF(route_train_6_direction, '') AS route_train_6_direction,

      -- =========================================================================
      -- SUBWAY
      -- =========================================================================
      NULLIF(route_subway_1_ref, '') AS route_subway_1_ref,
      NULLIF(route_subway_1_network, '') AS route_subway_1_network,
      NULLIF(route_subway_1_network_wikidata, '') AS route_subway_1_network_wikidata,
      NULLIF(route_subway_1_operator, '') AS route_subway_1_operator,
      NULLIF(route_subway_1_name, '') AS route_subway_1_name,
      NULLIF(route_subway_1_direction, '') AS route_subway_1_direction,

      NULLIF(route_subway_2_ref, '') AS route_subway_2_ref,
      NULLIF(route_subway_2_network, '') AS route_subway_2_network,
      NULLIF(route_subway_2_network_wikidata, '') AS route_subway_2_network_wikidata,
      NULLIF(route_subway_2_operator, '') AS route_subway_2_operator,
      NULLIF(route_subway_2_name, '') AS route_subway_2_name,
      NULLIF(route_subway_2_direction, '') AS route_subway_2_direction,

      NULLIF(route_subway_3_ref, '') AS route_subway_3_ref,
      NULLIF(route_subway_3_network, '') AS route_subway_3_network,
      NULLIF(route_subway_3_network_wikidata, '') AS route_subway_3_network_wikidata,
      NULLIF(route_subway_3_operator, '') AS route_subway_3_operator,
      NULLIF(route_subway_3_name, '') AS route_subway_3_name,
      NULLIF(route_subway_3_direction, '') AS route_subway_3_direction,

      NULLIF(route_subway_4_ref, '') AS route_subway_4_ref,
      NULLIF(route_subway_4_network, '') AS route_subway_4_network,
      NULLIF(route_subway_4_network_wikidata, '') AS route_subway_4_network_wikidata,
      NULLIF(route_subway_4_operator, '') AS route_subway_4_operator,
      NULLIF(route_subway_4_name, '') AS route_subway_4_name,
      NULLIF(route_subway_4_direction, '') AS route_subway_4_direction,

      NULLIF(route_subway_5_ref, '') AS route_subway_5_ref,
      NULLIF(route_subway_5_network, '') AS route_subway_5_network,
      NULLIF(route_subway_5_network_wikidata, '') AS route_subway_5_network_wikidata,
      NULLIF(route_subway_5_operator, '') AS route_subway_5_operator,
      NULLIF(route_subway_5_name, '') AS route_subway_5_name,
      NULLIF(route_subway_5_direction, '') AS route_subway_5_direction,

      NULLIF(route_subway_6_ref, '') AS route_subway_6_ref,
      NULLIF(route_subway_6_network, '') AS route_subway_6_network,
      NULLIF(route_subway_6_network_wikidata, '') AS route_subway_6_network_wikidata,
      NULLIF(route_subway_6_operator, '') AS route_subway_6_operator,
      NULLIF(route_subway_6_name, '') AS route_subway_6_name,
      NULLIF(route_subway_6_direction, '') AS route_subway_6_direction,

      -- =========================================================================
      -- LIGHT_RAIL
      -- =========================================================================
      NULLIF(route_light_rail_1_ref, '') AS route_light_rail_1_ref,
      NULLIF(route_light_rail_1_network, '') AS route_light_rail_1_network,
      NULLIF(route_light_rail_1_network_wikidata, '') AS route_light_rail_1_network_wikidata,
      NULLIF(route_light_rail_1_operator, '') AS route_light_rail_1_operator,
      NULLIF(route_light_rail_1_name, '') AS route_light_rail_1_name,
      NULLIF(route_light_rail_1_direction, '') AS route_light_rail_1_direction,

      NULLIF(route_light_rail_2_ref, '') AS route_light_rail_2_ref,
      NULLIF(route_light_rail_2_network, '') AS route_light_rail_2_network,
      NULLIF(route_light_rail_2_network_wikidata, '') AS route_light_rail_2_network_wikidata,
      NULLIF(route_light_rail_2_operator, '') AS route_light_rail_2_operator,
      NULLIF(route_light_rail_2_name, '') AS route_light_rail_2_name,
      NULLIF(route_light_rail_2_direction, '') AS route_light_rail_2_direction,

      NULLIF(route_light_rail_3_ref, '') AS route_light_rail_3_ref,
      NULLIF(route_light_rail_3_network, '') AS route_light_rail_3_network,
      NULLIF(route_light_rail_3_network_wikidata, '') AS route_light_rail_3_network_wikidata,
      NULLIF(route_light_rail_3_operator, '') AS route_light_rail_3_operator,
      NULLIF(route_light_rail_3_name, '') AS route_light_rail_3_name,
      NULLIF(route_light_rail_3_direction, '') AS route_light_rail_3_direction,

      NULLIF(route_light_rail_4_ref, '') AS route_light_rail_4_ref,
      NULLIF(route_light_rail_4_network, '') AS route_light_rail_4_network,
      NULLIF(route_light_rail_4_network_wikidata, '') AS route_light_rail_4_network_wikidata,
      NULLIF(route_light_rail_4_operator, '') AS route_light_rail_4_operator,
      NULLIF(route_light_rail_4_name, '') AS route_light_rail_4_name,
      NULLIF(route_light_rail_4_direction, '') AS route_light_rail_4_direction,

      NULLIF(route_light_rail_5_ref, '') AS route_light_rail_5_ref,
      NULLIF(route_light_rail_5_network, '') AS route_light_rail_5_network,
      NULLIF(route_light_rail_5_network_wikidata, '') AS route_light_rail_5_network_wikidata,
      NULLIF(route_light_rail_5_operator, '') AS route_light_rail_5_operator,
      NULLIF(route_light_rail_5_name, '') AS route_light_rail_5_name,
      NULLIF(route_light_rail_5_direction, '') AS route_light_rail_5_direction,

      NULLIF(route_light_rail_6_ref, '') AS route_light_rail_6_ref,
      NULLIF(route_light_rail_6_network, '') AS route_light_rail_6_network,
      NULLIF(route_light_rail_6_network_wikidata, '') AS route_light_rail_6_network_wikidata,
      NULLIF(route_light_rail_6_operator, '') AS route_light_rail_6_operator,
      NULLIF(route_light_rail_6_name, '') AS route_light_rail_6_name,
      NULLIF(route_light_rail_6_direction, '') AS route_light_rail_6_direction,

      -- =========================================================================
      -- TRAM
      -- =========================================================================
      NULLIF(route_tram_1_ref, '') AS route_tram_1_ref,
      NULLIF(route_tram_1_network, '') AS route_tram_1_network,
      NULLIF(route_tram_1_network_wikidata, '') AS route_tram_1_network_wikidata,
      NULLIF(route_tram_1_operator, '') AS route_tram_1_operator,
      NULLIF(route_tram_1_name, '') AS route_tram_1_name,
      NULLIF(route_tram_1_direction, '') AS route_tram_1_direction,

      NULLIF(route_tram_2_ref, '') AS route_tram_2_ref,
      NULLIF(route_tram_2_network, '') AS route_tram_2_network,
      NULLIF(route_tram_2_network_wikidata, '') AS route_tram_2_network_wikidata,
      NULLIF(route_tram_2_operator, '') AS route_tram_2_operator,
      NULLIF(route_tram_2_name, '') AS route_tram_2_name,
      NULLIF(route_tram_2_direction, '') AS route_tram_2_direction,

      NULLIF(route_tram_3_ref, '') AS route_tram_3_ref,
      NULLIF(route_tram_3_network, '') AS route_tram_3_network,
      NULLIF(route_tram_3_network_wikidata, '') AS route_tram_3_network_wikidata,
      NULLIF(route_tram_3_operator, '') AS route_tram_3_operator,
      NULLIF(route_tram_3_name, '') AS route_tram_3_name,
      NULLIF(route_tram_3_direction, '') AS route_tram_3_direction,

      NULLIF(route_tram_4_ref, '') AS route_tram_4_ref,
      NULLIF(route_tram_4_network, '') AS route_tram_4_network,
      NULLIF(route_tram_4_network_wikidata, '') AS route_tram_4_network_wikidata,
      NULLIF(route_tram_4_operator, '') AS route_tram_4_operator,
      NULLIF(route_tram_4_name, '') AS route_tram_4_name,
      NULLIF(route_tram_4_direction, '') AS route_tram_4_direction,

      NULLIF(route_tram_5_ref, '') AS route_tram_5_ref,
      NULLIF(route_tram_5_network, '') AS route_tram_5_network,
      NULLIF(route_tram_5_network_wikidata, '') AS route_tram_5_network_wikidata,
      NULLIF(route_tram_5_operator, '') AS route_tram_5_operator,
      NULLIF(route_tram_5_name, '') AS route_tram_5_name,
      NULLIF(route_tram_5_direction, '') AS route_tram_5_direction,

      NULLIF(route_tram_6_ref, '') AS route_tram_6_ref,
      NULLIF(route_tram_6_network, '') AS route_tram_6_network,
      NULLIF(route_tram_6_network_wikidata, '') AS route_tram_6_network_wikidata,
      NULLIF(route_tram_6_operator, '') AS route_tram_6_operator,
      NULLIF(route_tram_6_name, '') AS route_tram_6_name,
      NULLIF(route_tram_6_direction, '') AS route_tram_6_direction,

      -- =========================================================================
      -- TROLLEYBUS
      -- =========================================================================
      NULLIF(route_trolleybus_1_ref, '') AS route_trolleybus_1_ref,
      NULLIF(route_trolleybus_1_network, '') AS route_trolleybus_1_network,
      NULLIF(route_trolleybus_1_network_wikidata, '') AS route_trolleybus_1_network_wikidata,
      NULLIF(route_trolleybus_1_operator, '') AS route_trolleybus_1_operator,
      NULLIF(route_trolleybus_1_name, '') AS route_trolleybus_1_name,
      NULLIF(route_trolleybus_1_direction, '') AS route_trolleybus_1_direction,

      NULLIF(route_trolleybus_2_ref, '') AS route_trolleybus_2_ref,
      NULLIF(route_trolleybus_2_network, '') AS route_trolleybus_2_network,
      NULLIF(route_trolleybus_2_network_wikidata, '') AS route_trolleybus_2_network_wikidata,
      NULLIF(route_trolleybus_2_operator, '') AS route_trolleybus_2_operator,
      NULLIF(route_trolleybus_2_name, '') AS route_trolleybus_2_name,
      NULLIF(route_trolleybus_2_direction, '') AS route_trolleybus_2_direction,

      NULLIF(route_trolleybus_3_ref, '') AS route_trolleybus_3_ref,
      NULLIF(route_trolleybus_3_network, '') AS route_trolleybus_3_network,
      NULLIF(route_trolleybus_3_network_wikidata, '') AS route_trolleybus_3_network_wikidata,
      NULLIF(route_trolleybus_3_operator, '') AS route_trolleybus_3_operator,
      NULLIF(route_trolleybus_3_name, '') AS route_trolleybus_3_name,
      NULLIF(route_trolleybus_3_direction, '') AS route_trolleybus_3_direction,

      NULLIF(route_trolleybus_4_ref, '') AS route_trolleybus_4_ref,
      NULLIF(route_trolleybus_4_network, '') AS route_trolleybus_4_network,
      NULLIF(route_trolleybus_4_network_wikidata, '') AS route_trolleybus_4_network_wikidata,
      NULLIF(route_trolleybus_4_operator, '') AS route_trolleybus_4_operator,
      NULLIF(route_trolleybus_4_name, '') AS route_trolleybus_4_name,
      NULLIF(route_trolleybus_4_direction, '') AS route_trolleybus_4_direction,

      NULLIF(route_trolleybus_5_ref, '') AS route_trolleybus_5_ref,
      NULLIF(route_trolleybus_5_network, '') AS route_trolleybus_5_network,
      NULLIF(route_trolleybus_5_network_wikidata, '') AS route_trolleybus_5_network_wikidata,
      NULLIF(route_trolleybus_5_operator, '') AS route_trolleybus_5_operator,
      NULLIF(route_trolleybus_5_name, '') AS route_trolleybus_5_name,
      NULLIF(route_trolleybus_5_direction, '') AS route_trolleybus_5_direction,

      NULLIF(route_trolleybus_6_ref, '') AS route_trolleybus_6_ref,
      NULLIF(route_trolleybus_6_network, '') AS route_trolleybus_6_network,
      NULLIF(route_trolleybus_6_network_wikidata, '') AS route_trolleybus_6_network_wikidata,
      NULLIF(route_trolleybus_6_operator, '') AS route_trolleybus_6_operator,
      NULLIF(route_trolleybus_6_name, '') AS route_trolleybus_6_name,
      NULLIF(route_trolleybus_6_direction, '') AS route_trolleybus_6_direction,

      -- =========================================================================
      -- BUS
      -- =========================================================================
      NULLIF(route_bus_1_ref, '') AS route_bus_1_ref,
      NULLIF(route_bus_1_network, '') AS route_bus_1_network,
      NULLIF(route_bus_1_network_wikidata, '') AS route_bus_1_network_wikidata,
      NULLIF(route_bus_1_operator, '') AS route_bus_1_operator,
      NULLIF(route_bus_1_name, '') AS route_bus_1_name,
      NULLIF(route_bus_1_direction, '') AS route_bus_1_direction,

      NULLIF(route_bus_2_ref, '') AS route_bus_2_ref,
      NULLIF(route_bus_2_network, '') AS route_bus_2_network,
      NULLIF(route_bus_2_network_wikidata, '') AS route_bus_2_network_wikidata,
      NULLIF(route_bus_2_operator, '') AS route_bus_2_operator,
      NULLIF(route_bus_2_name, '') AS route_bus_2_name,
      NULLIF(route_bus_2_direction, '') AS route_bus_2_direction,

      NULLIF(route_bus_3_ref, '') AS route_bus_3_ref,
      NULLIF(route_bus_3_network, '') AS route_bus_3_network,
      NULLIF(route_bus_3_network_wikidata, '') AS route_bus_3_network_wikidata,
      NULLIF(route_bus_3_operator, '') AS route_bus_3_operator,
      NULLIF(route_bus_3_name, '') AS route_bus_3_name,
      NULLIF(route_bus_3_direction, '') AS route_bus_3_direction,

      NULLIF(route_bus_4_ref, '') AS route_bus_4_ref,
      NULLIF(route_bus_4_network, '') AS route_bus_4_network,
      NULLIF(route_bus_4_network_wikidata, '') AS route_bus_4_network_wikidata,
      NULLIF(route_bus_4_operator, '') AS route_bus_4_operator,
      NULLIF(route_bus_4_name, '') AS route_bus_4_name,
      NULLIF(route_bus_4_direction, '') AS route_bus_4_direction,

      NULLIF(route_bus_5_ref, '') AS route_bus_5_ref,
      NULLIF(route_bus_5_network, '') AS route_bus_5_network,
      NULLIF(route_bus_5_network_wikidata, '') AS route_bus_5_network_wikidata,
      NULLIF(route_bus_5_operator, '') AS route_bus_5_operator,
      NULLIF(route_bus_5_name, '') AS route_bus_5_name,
      NULLIF(route_bus_5_direction, '') AS route_bus_5_direction,

      NULLIF(route_bus_6_ref, '') AS route_bus_6_ref,
      NULLIF(route_bus_6_network, '') AS route_bus_6_network,
      NULLIF(route_bus_6_network_wikidata, '') AS route_bus_6_network_wikidata,
      NULLIF(route_bus_6_operator, '') AS route_bus_6_operator,
      NULLIF(route_bus_6_name, '') AS route_bus_6_name,
      NULLIF(route_bus_6_direction, '') AS route_bus_6_direction

    FROM mv_routes_indexed
    WITH DATA;

    -- Índice único (con todas las columnas *_ref)
    CREATE UNIQUE INDEX IF NOT EXISTS %I_way_id_idx
      ON %I (
        osm_id,
        start_decdate,
        end_decdate
      );

    -- Índice espacial
    CREATE INDEX IF NOT EXISTS %I_geom_idx
      ON %I USING GIST (geometry);
  $f$,
    full_view_name, full_view_name,
    simplify_tol::text, simplify_tol::text,
    full_view_name, full_view_name,
    full_view_name, full_view_name
  );

  RAISE NOTICE 'Ejecutando creación de %', full_view_name;
  EXECUTE sql;
  RAISE NOTICE 'Materialized view % creada/actualizada', full_view_name;
END;
$$ LANGUAGE plpgsql;

SELECT create_mv_routes_by_length('mv_routes_indexed_z5_6', 1000);
SELECT create_mv_routes_by_length('mv_routes_indexed_z7_8', 300);
SELECT create_mv_routes_by_length('mv_routes_indexed_z9_10', 100);
SELECT create_mv_routes_by_length('mv_routes_indexed_z11_12', 10);
SELECT create_mv_routes_by_length('mv_routes_indexed_z13_14', 1);
SELECT create_mv_routes_by_length('mv_routes_indexed_z15_20', 0);
