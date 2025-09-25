-- ============================================================================
-- STEP 1: Drop old indexed view if exists
-- ============================================================================
-- Why: We drop the existing materialized view to ensure the new structure
-- (new columns, different ranking logic) is created cleanly. We use CASCADE
-- to remove dependent objects (if any). Re-creation below will populate fresh data.
DROP MATERIALIZED VIEW IF EXISTS mv_routes_indexed CASCADE;

-- ============================================================================
-- STEP 2: Create the typed indexed view (exploded -> ranked -> aggregated)
-- ============================================================================
-- Purpose:
--  - Expand the JSON array of routes into one row per route (exploded)
--  - Compute a per-route priority score using route_priority(type, network, ref)
--  - Rank routes per (way_id, date-range, type) so we can fill fixed slots
--    (route_<type>_<n>_ref, route_<type>_<n>_network, route_<type>_<n>_network_wikidata,
--     route_<type>_<n>_operator, route_<type>_<n>_name) up to 6 slots.
--
-- Why this matters:
--  - Partitioning by `type` prevents mixing different route categories in the same
--    slot: stylesheets and renderers can focus on route_road_* vs route_bus_*.
--  - Fixed slots (1..6) enable efficient templating and indexing in downstream code.
--  - Keeping the original JSON `routes` column is a safe fallback for edge cases.

CREATE MATERIALIZED VIEW mv_routes_indexed AS
WITH exploded AS (
  -- Expand JSONB array 'routes' into individual route rows.
  -- We also extract 'network:wikidata' if present, and compute a priority score.
  SELECT
    n.way_id,
    n.min_start_decdate,
    n.max_end_decdate,
    n.min_start_date_iso,
    n.max_end_date_iso,
    n.geometry,
    n.num_routes,
    r.value ->> 'ref'                      AS ref,
    r.value ->> 'network'                  AS network,
    r.value ->> 'network:wikidata'         AS network_wikidata,
    r.value ->> 'operator'                 AS operator,
    r.value ->> 'type'                     AS type,
    r.value ->> 'name'                     AS name,
    -- prio uses the function that considers type, network, ref.
    -- Larger prio = more important (we will ORDER BY prio DESC)
    route_priority(r.value ->> 'type', r.value ->> 'network', r.value ->> 'ref') AS prio,
    n.routes
  FROM mv_routes_normalized n
  CROSS JOIN LATERAL jsonb_array_elements(n.routes) r
),
ranked AS (
  -- Assign a rank for each route within the same way/date-range AND type.
  -- This ensures we can produce compact slots per type without gaps:
  --   type_rnk = 1  -> top route of this type
  --   type_rnk = 2  -> second, etc.
  --
  -- ORDER BY explanation:
  --  - (ref IS NOT NULL) DESC: prefer routes that have a 'ref' value (usually more informative)
  --  - prio DESC: break ties based on the computed priority score
  SELECT
    way_id,
    min_start_decdate,
    max_end_decdate,
    min_start_date_iso,
    max_end_date_iso,
    geometry,
    num_routes,
    routes,
    ref,
    network,
    network_wikidata,
    operator,
    type,
    name,
    prio,
    ROW_NUMBER() OVER (
      PARTITION BY way_id, min_start_decdate, max_end_decdate, type
      ORDER BY (ref IS NOT NULL) DESC, prio DESC
    ) AS type_rnk
  FROM exploded
)
SELECT
  -- identity / grouping columns
  way_id,
  min_start_decdate,
  max_end_decdate,
  min_start_date_iso,
  max_end_date_iso,
  geometry,
  num_routes,

  -- =========================================================================
  -- ROAD
  -- For each slot we store: ref, network, network_wikidata, operator, name.
  -- Rationale: roads often have multiple concurrent refs (I-5, US-101, etc.)
  -- and rendering needs explicit columns for each slot.
  -- =========================================================================
  MAX(CASE WHEN type = 'road' AND type_rnk = 1 THEN ref              END) AS route_road_1_ref,
  MAX(CASE WHEN type = 'road' AND type_rnk = 1 THEN network          END) AS route_road_1_network,
  MAX(CASE WHEN type = 'road' AND type_rnk = 1 THEN network_wikidata END) AS route_road_1_network_wikidata,
  MAX(CASE WHEN type = 'road' AND type_rnk = 1 THEN operator         END) AS route_road_1_operator,
  MAX(CASE WHEN type = 'road' AND type_rnk = 1 THEN name             END) AS route_road_1_name,

  MAX(CASE WHEN type = 'road' AND type_rnk = 2 THEN ref              END) AS route_road_2_ref,
  MAX(CASE WHEN type = 'road' AND type_rnk = 2 THEN network          END) AS route_road_2_network,
  MAX(CASE WHEN type = 'road' AND type_rnk = 2 THEN network_wikidata END) AS route_road_2_network_wikidata,
  MAX(CASE WHEN type = 'road' AND type_rnk = 2 THEN operator         END) AS route_road_2_operator,
  MAX(CASE WHEN type = 'road' AND type_rnk = 2 THEN name             END) AS route_road_2_name,

  MAX(CASE WHEN type = 'road' AND type_rnk = 3 THEN ref              END) AS route_road_3_ref,
  MAX(CASE WHEN type = 'road' AND type_rnk = 3 THEN network          END) AS route_road_3_network,
  MAX(CASE WHEN type = 'road' AND type_rnk = 3 THEN network_wikidata END) AS route_road_3_network_wikidata,
  MAX(CASE WHEN type = 'road' AND type_rnk = 3 THEN operator         END) AS route_road_3_operator,
  MAX(CASE WHEN type = 'road' AND type_rnk = 3 THEN name             END) AS route_road_3_name,

  MAX(CASE WHEN type = 'road' AND type_rnk = 4 THEN ref              END) AS route_road_4_ref,
  MAX(CASE WHEN type = 'road' AND type_rnk = 4 THEN network          END) AS route_road_4_network,
  MAX(CASE WHEN type = 'road' AND type_rnk = 4 THEN network_wikidata END) AS route_road_4_network_wikidata,
  MAX(CASE WHEN type = 'road' AND type_rnk = 4 THEN operator         END) AS route_road_4_operator,
  MAX(CASE WHEN type = 'road' AND type_rnk = 4 THEN name             END) AS route_road_4_name,

  MAX(CASE WHEN type = 'road' AND type_rnk = 5 THEN ref              END) AS route_road_5_ref,
  MAX(CASE WHEN type = 'road' AND type_rnk = 5 THEN network          END) AS route_road_5_network,
  MAX(CASE WHEN type = 'road' AND type_rnk = 5 THEN network_wikidata END) AS route_road_5_network_wikidata,
  MAX(CASE WHEN type = 'road' AND type_rnk = 5 THEN operator         END) AS route_road_5_operator,
  MAX(CASE WHEN type = 'road' AND type_rnk = 5 THEN name             END) AS route_road_5_name,

  MAX(CASE WHEN type = 'road' AND type_rnk = 6 THEN ref              END) AS route_road_6_ref,
  MAX(CASE WHEN type = 'road' AND type_rnk = 6 THEN network          END) AS route_road_6_network,
  MAX(CASE WHEN type = 'road' AND type_rnk = 6 THEN network_wikidata END) AS route_road_6_network_wikidata,
  MAX(CASE WHEN type = 'road' AND type_rnk = 6 THEN operator         END) AS route_road_6_operator,
  MAX(CASE WHEN type = 'road' AND type_rnk = 6 THEN name             END) AS route_road_6_name,

  -- =========================================================================
  -- TRAIN
  -- =========================================================================
  MAX(CASE WHEN type = 'train' AND type_rnk = 1 THEN ref              END) AS route_train_1_ref,
  MAX(CASE WHEN type = 'train' AND type_rnk = 1 THEN network          END) AS route_train_1_network,
  MAX(CASE WHEN type = 'train' AND type_rnk = 1 THEN network_wikidata END) AS route_train_1_network_wikidata,
  MAX(CASE WHEN type = 'train' AND type_rnk = 1 THEN operator         END) AS route_train_1_operator,
  MAX(CASE WHEN type = 'train' AND type_rnk = 1 THEN name             END) AS route_train_1_name,

  MAX(CASE WHEN type = 'train' AND type_rnk = 2 THEN ref              END) AS route_train_2_ref,
  MAX(CASE WHEN type = 'train' AND type_rnk = 2 THEN network          END) AS route_train_2_network,
  MAX(CASE WHEN type = 'train' AND type_rnk = 2 THEN network_wikidata END) AS route_train_2_network_wikidata,
  MAX(CASE WHEN type = 'train' AND type_rnk = 2 THEN operator         END) AS route_train_2_operator,
  MAX(CASE WHEN type = 'train' AND type_rnk = 2 THEN name             END) AS route_train_2_name,

  MAX(CASE WHEN type = 'train' AND type_rnk = 3 THEN ref              END) AS route_train_3_ref,
  MAX(CASE WHEN type = 'train' AND type_rnk = 3 THEN network          END) AS route_train_3_network,
  MAX(CASE WHEN type = 'train' AND type_rnk = 3 THEN network_wikidata END) AS route_train_3_network_wikidata,
  MAX(CASE WHEN type = 'train' AND type_rnk = 3 THEN operator         END) AS route_train_3_operator,
  MAX(CASE WHEN type = 'train' AND type_rnk = 3 THEN name             END) AS route_train_3_name,

  MAX(CASE WHEN type = 'train' AND type_rnk = 4 THEN ref              END) AS route_train_4_ref,
  MAX(CASE WHEN type = 'train' AND type_rnk = 4 THEN network          END) AS route_train_4_network,
  MAX(CASE WHEN type = 'train' AND type_rnk = 4 THEN network_wikidata END) AS route_train_4_network_wikidata,
  MAX(CASE WHEN type = 'train' AND type_rnk = 4 THEN operator         END) AS route_train_4_operator,
  MAX(CASE WHEN type = 'train' AND type_rnk = 4 THEN name             END) AS route_train_4_name,

  MAX(CASE WHEN type = 'train' AND type_rnk = 5 THEN ref              END) AS route_train_5_ref,
  MAX(CASE WHEN type = 'train' AND type_rnk = 5 THEN network          END) AS route_train_5_network,
  MAX(CASE WHEN type = 'train' AND type_rnk = 5 THEN network_wikidata END) AS route_train_5_network_wikidata,
  MAX(CASE WHEN type = 'train' AND type_rnk = 5 THEN operator         END) AS route_train_5_operator,
  MAX(CASE WHEN type = 'train' AND type_rnk = 5 THEN name             END) AS route_train_5_name,

  MAX(CASE WHEN type = 'train' AND type_rnk = 6 THEN ref              END) AS route_train_6_ref,
  MAX(CASE WHEN type = 'train' AND type_rnk = 6 THEN network          END) AS route_train_6_network,
  MAX(CASE WHEN type = 'train' AND type_rnk = 6 THEN network_wikidata END) AS route_train_6_network_wikidata,
  MAX(CASE WHEN type = 'train' AND type_rnk = 6 THEN operator         END) AS route_train_6_operator,
  MAX(CASE WHEN type = 'train' AND type_rnk = 6 THEN name             END) AS route_train_6_name,

  -- =========================================================================
  -- SUBWAY
  -- =========================================================================
  MAX(CASE WHEN type = 'subway' AND type_rnk = 1 THEN ref              END) AS route_subway_1_ref,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 1 THEN network          END) AS route_subway_1_network,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 1 THEN network_wikidata END) AS route_subway_1_network_wikidata,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 1 THEN operator         END) AS route_subway_1_operator,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 1 THEN name             END) AS route_subway_1_name,
  -- ... repeat slots 2..6 for subway
  MAX(CASE WHEN type = 'subway' AND type_rnk = 2 THEN ref              END) AS route_subway_2_ref,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 2 THEN network          END) AS route_subway_2_network,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 2 THEN network_wikidata END) AS route_subway_2_network_wikidata,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 2 THEN operator         END) AS route_subway_2_operator,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 2 THEN name             END) AS route_subway_2_name,

  MAX(CASE WHEN type = 'subway' AND type_rnk = 3 THEN ref              END) AS route_subway_3_ref,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 3 THEN network          END) AS route_subway_3_network,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 3 THEN network_wikidata END) AS route_subway_3_network_wikidata,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 3 THEN operator         END) AS route_subway_3_operator,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 3 THEN name             END) AS route_subway_3_name,

  MAX(CASE WHEN type = 'subway' AND type_rnk = 4 THEN ref              END) AS route_subway_4_ref,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 4 THEN network          END) AS route_subway_4_network,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 4 THEN network_wikidata END) AS route_subway_4_network_wikidata,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 4 THEN operator         END) AS route_subway_4_operator,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 4 THEN name             END) AS route_subway_4_name,

  MAX(CASE WHEN type = 'subway' AND type_rnk = 5 THEN ref              END) AS route_subway_5_ref,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 5 THEN network          END) AS route_subway_5_network,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 5 THEN network_wikidata END) AS route_subway_5_network_wikidata,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 5 THEN operator         END) AS route_subway_5_operator,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 5 THEN name             END) AS route_subway_5_name,

  MAX(CASE WHEN type = 'subway' AND type_rnk = 6 THEN ref              END) AS route_subway_6_ref,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 6 THEN network          END) AS route_subway_6_network,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 6 THEN network_wikidata END) AS route_subway_6_network_wikidata,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 6 THEN operator         END) AS route_subway_6_operator,
  MAX(CASE WHEN type = 'subway' AND type_rnk = 6 THEN name             END) AS route_subway_6_name,

  -- =========================================================================
  -- LIGHT_RAIL
  -- =========================================================================
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 1 THEN ref              END) AS route_light_rail_1_ref,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 1 THEN network          END) AS route_light_rail_1_network,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 1 THEN network_wikidata END) AS route_light_rail_1_network_wikidata,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 1 THEN operator         END) AS route_light_rail_1_operator,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 1 THEN name             END) AS route_light_rail_1_name,
  -- ... repeat slots 2..6 for light_rail
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 2 THEN ref              END) AS route_light_rail_2_ref,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 2 THEN network          END) AS route_light_rail_2_network,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 2 THEN network_wikidata END) AS route_light_rail_2_network_wikidata,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 2 THEN operator         END) AS route_light_rail_2_operator,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 2 THEN name             END) AS route_light_rail_2_name,

  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 3 THEN ref              END) AS route_light_rail_3_ref,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 3 THEN network          END) AS route_light_rail_3_network,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 3 THEN network_wikidata END) AS route_light_rail_3_network_wikidata,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 3 THEN operator         END) AS route_light_rail_3_operator,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 3 THEN name             END) AS route_light_rail_3_name,

  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 4 THEN ref              END) AS route_light_rail_4_ref,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 4 THEN network          END) AS route_light_rail_4_network,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 4 THEN network_wikidata END) AS route_light_rail_4_network_wikidata,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 4 THEN operator         END) AS route_light_rail_4_operator,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 4 THEN name             END) AS route_light_rail_4_name,

  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 5 THEN ref              END) AS route_light_rail_5_ref,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 5 THEN network          END) AS route_light_rail_5_network,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 5 THEN network_wikidata END) AS route_light_rail_5_network_wikidata,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 5 THEN operator         END) AS route_light_rail_5_operator,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 5 THEN name             END) AS route_light_rail_5_name,

  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 6 THEN ref              END) AS route_light_rail_6_ref,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 6 THEN network          END) AS route_light_rail_6_network,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 6 THEN network_wikidata END) AS route_light_rail_6_network_wikidata,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 6 THEN operator         END) AS route_light_rail_6_operator,
  MAX(CASE WHEN type = 'light_rail' AND type_rnk = 6 THEN name             END) AS route_light_rail_6_name,

  -- =========================================================================
  -- TRAM
  -- =========================================================================
  MAX(CASE WHEN type = 'tram' AND type_rnk = 1 THEN ref              END) AS route_tram_1_ref,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 1 THEN network          END) AS route_tram_1_network,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 1 THEN network_wikidata END) AS route_tram_1_network_wikidata,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 1 THEN operator         END) AS route_tram_1_operator,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 1 THEN name             END) AS route_tram_1_name,
  -- ... repeat slots 2..6 for tram
  MAX(CASE WHEN type = 'tram' AND type_rnk = 2 THEN ref              END) AS route_tram_2_ref,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 2 THEN network          END) AS route_tram_2_network,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 2 THEN network_wikidata END) AS route_tram_2_network_wikidata,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 2 THEN operator         END) AS route_tram_2_operator,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 2 THEN name             END) AS route_tram_2_name,

  MAX(CASE WHEN type = 'tram' AND type_rnk = 3 THEN ref              END) AS route_tram_3_ref,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 3 THEN network          END) AS route_tram_3_network,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 3 THEN network_wikidata END) AS route_tram_3_network_wikidata,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 3 THEN operator         END) AS route_tram_3_operator,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 3 THEN name             END) AS route_tram_3_name,

  MAX(CASE WHEN type = 'tram' AND type_rnk = 4 THEN ref              END) AS route_tram_4_ref,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 4 THEN network          END) AS route_tram_4_network,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 4 THEN network_wikidata END) AS route_tram_4_network_wikidata,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 4 THEN operator         END) AS route_tram_4_operator,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 4 THEN name             END) AS route_tram_4_name,

  MAX(CASE WHEN type = 'tram' AND type_rnk = 5 THEN ref              END) AS route_tram_5_ref,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 5 THEN network          END) AS route_tram_5_network,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 5 THEN network_wikidata END) AS route_tram_5_network_wikidata,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 5 THEN operator         END) AS route_tram_5_operator,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 5 THEN name             END) AS route_tram_5_name,

  MAX(CASE WHEN type = 'tram' AND type_rnk = 6 THEN ref              END) AS route_tram_6_ref,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 6 THEN network          END) AS route_tram_6_network,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 6 THEN network_wikidata END) AS route_tram_6_network_wikidata,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 6 THEN operator         END) AS route_tram_6_operator,
  MAX(CASE WHEN type = 'tram' AND type_rnk = 6 THEN name             END) AS route_tram_6_name,

  -- =========================================================================
  -- TROLLEYBUS
  -- =========================================================================
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 1 THEN ref              END) AS route_trolleybus_1_ref,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 1 THEN network          END) AS route_trolleybus_1_network,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 1 THEN network_wikidata END) AS route_trolleybus_1_network_wikidata,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 1 THEN operator         END) AS route_trolleybus_1_operator,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 1 THEN name             END) AS route_trolleybus_1_name,
  -- ... repeat slots 2..6 for trolleybus
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 2 THEN ref              END) AS route_trolleybus_2_ref,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 2 THEN network          END) AS route_trolleybus_2_network,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 2 THEN network_wikidata END) AS route_trolleybus_2_network_wikidata,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 2 THEN operator         END) AS route_trolleybus_2_operator,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 2 THEN name             END) AS route_trolleybus_2_name,

  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 3 THEN ref              END) AS route_trolleybus_3_ref,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 3 THEN network          END) AS route_trolleybus_3_network,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 3 THEN network_wikidata END) AS route_trolleybus_3_network_wikidata,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 3 THEN operator         END) AS route_trolleybus_3_operator,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 3 THEN name             END) AS route_trolleybus_3_name,

  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 4 THEN ref              END) AS route_trolleybus_4_ref,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 4 THEN network          END) AS route_trolleybus_4_network,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 4 THEN network_wikidata END) AS route_trolleybus_4_network_wikidata,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 4 THEN operator         END) AS route_trolleybus_4_operator,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 4 THEN name             END) AS route_trolleybus_4_name,

  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 5 THEN ref              END) AS route_trolleybus_5_ref,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 5 THEN network          END) AS route_trolleybus_5_network,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 5 THEN network_wikidata END) AS route_trolleybus_5_network_wikidata,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 5 THEN operator         END) AS route_trolleybus_5_operator,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 5 THEN name             END) AS route_trolleybus_5_name,

  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 6 THEN ref              END) AS route_trolleybus_6_ref,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 6 THEN network          END) AS route_trolleybus_6_network,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 6 THEN network_wikidata END) AS route_trolleybus_6_network_wikidata,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 6 THEN operator         END) AS route_trolleybus_6_operator,
  MAX(CASE WHEN type = 'trolleybus' AND type_rnk = 6 THEN name             END) AS route_trolleybus_6_name,

  -- =========================================================================
  -- BUS
  -- =========================================================================
  MAX(CASE WHEN type = 'bus' AND type_rnk = 1 THEN ref              END) AS route_bus_1_ref,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 1 THEN network          END) AS route_bus_1_network,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 1 THEN network_wikidata END) AS route_bus_1_network_wikidata,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 1 THEN operator         END) AS route_bus_1_operator,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 1 THEN name             END) AS route_bus_1_name,

  MAX(CASE WHEN type = 'bus' AND type_rnk = 2 THEN ref              END) AS route_bus_2_ref,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 2 THEN network          END) AS route_bus_2_network,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 2 THEN network_wikidata END) AS route_bus_2_network_wikidata,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 2 THEN operator         END) AS route_bus_2_operator,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 2 THEN name             END) AS route_bus_2_name,

  MAX(CASE WHEN type = 'bus' AND type_rnk = 3 THEN ref              END) AS route_bus_3_ref,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 3 THEN network          END) AS route_bus_3_network,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 3 THEN network_wikidata END) AS route_bus_3_network_wikidata,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 3 THEN operator         END) AS route_bus_3_operator,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 3 THEN name             END) AS route_bus_3_name,

  MAX(CASE WHEN type = 'bus' AND type_rnk = 4 THEN ref              END) AS route_bus_4_ref,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 4 THEN network          END) AS route_bus_4_network,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 4 THEN network_wikidata END) AS route_bus_4_network_wikidata,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 4 THEN operator         END) AS route_bus_4_operator,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 4 THEN name             END) AS route_bus_4_name,

  MAX(CASE WHEN type = 'bus' AND type_rnk = 5 THEN ref              END) AS route_bus_5_ref,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 5 THEN network          END) AS route_bus_5_network,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 5 THEN network_wikidata END) AS route_bus_5_network_wikidata,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 5 THEN operator         END) AS route_bus_5_operator,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 5 THEN name             END) AS route_bus_5_name,

  MAX(CASE WHEN type = 'bus' AND type_rnk = 6 THEN ref              END) AS route_bus_6_ref,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 6 THEN network          END) AS route_bus_6_network,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 6 THEN network_wikidata END) AS route_bus_6_network_wikidata,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 6 THEN operator         END) AS route_bus_6_operator,
  MAX(CASE WHEN type = 'bus' AND type_rnk = 6 THEN name             END) AS route_bus_6_name,

  -- =========================================================================
  -- keep the original JSON array as fallback (useful for edge-cases and debug)
  -- =========================================================================
  routes

FROM ranked
WHERE type IN ('road', 'train', 'subway', 'light_rail', 'tram', 'trolleybus', 'bus')
GROUP BY
  way_id, min_start_decdate, max_end_decdate,
  min_start_date_iso, max_end_date_iso,
  geometry, num_routes, routes
WITH DATA;

-- ============================================================================
-- STEP 3: Indexes
-- ============================================================================
-- Why:
--  - Unique index ensures single row per (way_id, date-range) combination.
--  - Date index helps queries filtering by validity interval.
--  - GIST geometry index is essential for spatial queries (bounding boxes, joins).
CREATE UNIQUE INDEX mv_routes_indexed_uidx
  ON mv_routes_indexed (way_id, min_start_decdate, max_end_decdate);

CREATE INDEX mv_routes_indexed_dates_idx
  ON mv_routes_indexed (min_start_decdate, max_end_decdate);

CREATE INDEX mv_routes_indexed_geom_idx
  ON mv_routes_indexed USING GIST (geometry);

-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_routes_indexed;