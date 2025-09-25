DROP FUNCTION IF EXISTS route_priority(text, text, text);

CREATE OR REPLACE FUNCTION route_priority(type TEXT, network TEXT, ref TEXT)
RETURNS NUMERIC AS $$
DECLARE
  colon_count INT;   -- number of ':' in the network string (proxy for hierarchy depth)
  ref_num INT;       -- numeric part extracted from 'ref' (e.g., I-80 -> 80)
  score NUMERIC;     -- final computed score
  base NUMERIC;      -- large "base block" depending on route type
  net_bonus NUMERIC; -- additional bonus for some specific networks
BEGIN
  ---------------------------------------------------------------------------
  -- STEP 1: Assign a "base priority" depending on the ROUTE TYPE.
  --
  -- Why: This ensures that entire categories rank above others.
  -- For example, 'road' routes should always outrank 'bus' routes, even if
  -- the bus has a very low route number like "bus 1".
  --
  -- The values are big (10^12, 9*10^11, etc.) to create "safe gaps".
  -- That way, refinements inside each type (from colon_count or ref_num)
  -- can never overlap across types.
  ---------------------------------------------------------------------------
  base := CASE type
             WHEN 'road'        THEN 1000000000000  -- highest global priority
             WHEN 'train'       THEN  900000000000
             WHEN 'subway'      THEN  850000000000
             WHEN 'light_rail'  THEN  800000000000
             WHEN 'tram'        THEN  750000000000
             WHEN 'trolleybus'  THEN  700000000000
             WHEN 'bus'         THEN  650000000000  -- lowest public transport category
             ELSE               100000000000       -- fallback for unknown types
          END;

  ---------------------------------------------------------------------------
  -- STEP 2: Add a "network bonus" for special-cased networks.
  --
  -- Why: Even at the same colon_count level, some networks are more
  -- important than others. For example:
  --   - In the US, "US:I" (Interstates) are more important than "US:US"
  --     (US Highways), which are more important than "US:CA" (California).
  --   - More generally, "*:national" outranks "*:regional".
  --
  -- This block encodes domain knowledge of important networks so they
  -- always sort ahead of less important but similar-level networks.
  ---------------------------------------------------------------------------
  net_bonus := CASE 
                 WHEN network = 'US:I'            THEN 1000000 -- Interstates come first
                 WHEN network = 'US:US'           THEN  900000 -- then US Highways
                 WHEN network LIKE 'US:CA%'       THEN  800000 -- then State Highways
                 WHEN network LIKE '%:national'   THEN  700000 -- then national routes
                 WHEN network LIKE '%:regional'   THEN  600000 -- then regional routes
                 ELSE 0
               END;

  ---------------------------------------------------------------------------
  -- STEP 3: Fine-grained refinements inside each TYPE
  --
  -- For 'road':
  --   - colon_count: counts how many ':' separators are in the network.
  --     Fewer colons = higher-level network = higher priority.
  --     Example: "US:I" (1 colons) outranks "US:CA:XX" (2 colons).
  --
  --   - ref_num: if the route has a numeric reference, smaller numbers
  --     often indicate more important or primary routes. Example:
  --       - "I-5" is a backbone route → higher priority.
  --       - "I-495" is more local → lower priority.
  --     If no numeric found, we default to a large value (999999).
  --     e.g
  --       I	0	A pure top-level network (rare coding)
  --       US:I	1	US Interstate
  --       US:US	1	US Highway
  --       US:CA	1	California State Highways
  --       US:CA:XX	2	Subnetwork of CA (more specific)
  --
  -- For non-road types:
  --   We don't have similarly strong global rules.
  --   Instead, we apply the base + net_bonus, with a small tie-breaker:
  --   shorter network names win slightly, to keep consistency.
  ---------------------------------------------------------------------------
  IF type = 'road' THEN
    -- count sublevel depth from ':' in network string
    colon_count := length(COALESCE(network,'')) - length(replace(COALESCE(network,''), ':',''));

    -- try to extract numeric part of ref
    BEGIN
      ref_num := NULLIF(regexp_replace(ref, '\D','','g'), '')::INT;
    EXCEPTION WHEN others THEN
      ref_num := 999999; -- fallback if parsing fails
    END;
    IF ref_num IS NULL THEN
      ref_num := 999999;
    END IF;

    -- compute final score for roads
    score := base
          + net_bonus                                       -- domain-specific boost
          + (100 - colon_count) * 1000000000::NUMERIC       -- higher-level networks first
          + (1000000::NUMERIC - ref_num);                   -- smaller ref numbers outrank
  ELSE
    -- simple fallback logic for public transport, etc.
    score := base
          + net_bonus                                       -- still allow bonuses
          + (1000 - length(COALESCE(network,'')));          -- shorter networks win ties
  END IF;

  ---------------------------------------------------------------------------
  -- STEP 4: Return the computed score
  --
  -- Bigger number = higher priority.
  -- This score is later used in ROW_NUMBER() OVER (ORDER BY prio DESC),
  -- so that the most important route for each type always occupies slot 1,
  -- then slot 2, etc.
  ---------------------------------------------------------------------------
  RETURN score;
END;
$$ LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE;


-- Generates a SQL fragment defining route-specific columns for a given route type
-- and number of slots (e.g., route_bus_1_ref, route_bus_2_ref, etc.).
-- Intended for use in dynamic SELECT clauses to pivot concurrent routes by type
-- and rank, enabling stylesheet-friendly, type-separated route rendering.
-- Each slot corresponds to a position (type_rnk) within the same route type.
-- Returns a comma-separated list of column definitions without a trailing comma.

CREATE OR REPLACE FUNCTION generate_route_columns(route_type TEXT, slot_count INT)
RETURNS TEXT AS $$
DECLARE
  i INT;
  col TEXT := '';
BEGIN
  FOR i IN 1..slot_count LOOP
    col := col || format(
      E'MAX(CASE WHEN type = %L AND type_rnk = %s THEN ref              END) AS route_%s_%s_ref,\n'
      || '  MAX(CASE WHEN type = %1$L AND type_rnk = %2$s THEN network          END) AS route_%3$s_%2$s_network,\n'
      || '  MAX(CASE WHEN type = %1$L AND type_rnk = %2$s THEN network_wikidata END) AS route_%3$s_%2$s_network_wikidata,\n'
      || '  MAX(CASE WHEN type = %1$L AND type_rnk = %2$s THEN operator         END) AS route_%3$s_%2$s_operator,\n'
      || '  MAX(CASE WHEN type = %1$L AND type_rnk = %2$s THEN name             END) AS route_%3$s_%2$s_name,\n',
      route_type, i, route_type, i
    );
  END LOOP;
  RETURN trim(trailing E',\n' from col);
END;
$$ LANGUAGE plpgsql;