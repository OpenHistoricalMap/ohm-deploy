
-- ============================================================================
-- STEP 1: Drop old indexed view if exists
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS mv_routes_indexed CASCADE;

-- ============================================================================
-- STEP 2: Create the compact indexed view
-- ============================================================================
CREATE MATERIALIZED VIEW mv_routes_indexed AS
WITH exploded AS (
  -- Expand JSON array of routes into one row per route
  SELECT
    n.way_id,
    n.min_start_decdate,
    n.max_end_decdate,
    n.min_start_date_iso,
    n.max_end_date_iso,
    n.geometry,
    n.num_routes,
    r.value ->> 'ref'      AS ref,
    r.value ->> 'network'  AS network,
    r.value ->> 'operator' AS operator,
    r.value ->> 'type'     AS type,
    r.value ->> 'name'     AS name,
    route_priority(r.value ->> 'network', r.value ->> 'ref') AS prio,
    n.routes
  FROM mv_routes_normalized n
  CROSS JOIN LATERAL jsonb_array_elements(n.routes) r
),
ranked AS (
  -- Assign two ranks:
  --   full_rnk    → just by priority
  --   compact_rnk → skips NULL refs, ensures route1_ref will always be filled
  SELECT
    way_id,
    min_start_decdate,
    max_end_decdate,
    min_start_date_iso,
    max_end_date_iso,
    geometry,
    num_routes,
    routes,
    ref, network, operator, type, name,
    ROW_NUMBER() OVER (
      PARTITION BY way_id, min_start_decdate, max_end_decdate
      ORDER BY prio DESC
    ) AS full_rnk,
    ROW_NUMBER() OVER (
      PARTITION BY way_id, min_start_decdate, max_end_decdate
      ORDER BY (ref IS NOT NULL) DESC, prio DESC
    ) AS compact_rnk
  FROM exploded
)
SELECT
  way_id,
  min_start_decdate,
  max_end_decdate,
  min_start_date_iso,
  max_end_date_iso,
  geometry,
  num_routes,

  -- top 6 slots compacted (no gaps)
  MAX(CASE WHEN compact_rnk = 1 THEN ref      END) AS route_1_ref,
  MAX(CASE WHEN compact_rnk = 1 THEN network  END) AS route_1_network,
  MAX(CASE WHEN compact_rnk = 1 THEN operator END) AS route_1_operator,
  MAX(CASE WHEN compact_rnk = 1 THEN type     END) AS route_1_type,
  MAX(CASE WHEN compact_rnk = 1 THEN name     END) AS route_1_name,

  MAX(CASE WHEN compact_rnk = 2 THEN ref      END) AS route_2_ref,
  MAX(CASE WHEN compact_rnk = 2 THEN network  END) AS route_2_network,
  MAX(CASE WHEN compact_rnk = 2 THEN operator END) AS route_2_operator,
  MAX(CASE WHEN compact_rnk = 2 THEN type     END) AS route_2_type,
  MAX(CASE WHEN compact_rnk = 2 THEN name     END) AS route_2_name,

  MAX(CASE WHEN compact_rnk = 3 THEN ref      END) AS route_3_ref,
  MAX(CASE WHEN compact_rnk = 3 THEN network  END) AS route_3_network,
  MAX(CASE WHEN compact_rnk = 3 THEN operator END) AS route_3_operator,
  MAX(CASE WHEN compact_rnk = 3 THEN type     END) AS route_3_type,
  MAX(CASE WHEN compact_rnk = 3 THEN name     END) AS route_3_name,

  MAX(CASE WHEN compact_rnk = 4 THEN ref      END) AS route_4_ref,
  MAX(CASE WHEN compact_rnk = 4 THEN network  END) AS route_4_network,
  MAX(CASE WHEN compact_rnk = 4 THEN operator END) AS route_4_operator,
  MAX(CASE WHEN compact_rnk = 4 THEN type     END) AS route_4_type,
  MAX(CASE WHEN compact_rnk = 4 THEN name     END) AS route_4_name,

  MAX(CASE WHEN compact_rnk = 5 THEN ref      END) AS route_5_ref,
  MAX(CASE WHEN compact_rnk = 5 THEN network  END) AS route_5_network,
  MAX(CASE WHEN compact_rnk = 5 THEN operator END) AS route_5_operator,
  MAX(CASE WHEN compact_rnk = 5 THEN type     END) AS route_5_type,
  MAX(CASE WHEN compact_rnk = 5 THEN name     END) AS route_5_name,

  MAX(CASE WHEN compact_rnk = 6 THEN ref      END) AS route_6_ref,
  MAX(CASE WHEN compact_rnk = 6 THEN network  END) AS route_6_network,
  MAX(CASE WHEN compact_rnk = 6 THEN operator END) AS route_6_operator,
  MAX(CASE WHEN compact_rnk = 6 THEN type     END) AS route_6_type,
  MAX(CASE WHEN compact_rnk = 6 THEN name     END) AS route_6_name,

  -- keep full JSON array of routes as fallback
  routes

FROM ranked
GROUP BY
  way_id, min_start_decdate, max_end_decdate,
  min_start_date_iso, max_end_date_iso,
  geometry, num_routes, routes
WITH DATA;

-- ============================================================================
-- STEP 3: Indexes
-- ============================================================================
CREATE UNIQUE INDEX mv_routes_indexed_uidx
  ON mv_routes_indexed (way_id, min_start_decdate, max_end_decdate);

CREATE INDEX mv_routes_indexed_dates_idx
  ON mv_routes_indexed (min_start_decdate, max_end_decdate);

CREATE INDEX mv_routes_indexed_geom_idx
  ON mv_routes_indexed USING GIST (geometry);

-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_routes_indexed;
