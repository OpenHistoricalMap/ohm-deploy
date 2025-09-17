-- ============================================================================
-- Function: route_priority
-- Purpose:
--   Prioritize concurrent routes, following OpenMapTiles/Mapbox logic
--
-- Rules:
--   1. Networks with fewer ":" are ranked higher
--      (e.g. "us:i" > "us:state" > "us:county")
--   2. Within the same network, lower numeric ref is ranked higher
--      (e.g. US 20 before US 158)
--   3. If ref is not numeric, fallback with a large default so
--      those networks end up lower
--
-- Usage:
--   ORDER BY route_priority(network, ref) DESC
-- ============================================================================

DROP FUNCTION IF EXISTS route_priority(text,text);
CREATE OR REPLACE FUNCTION route_priority(network TEXT, ref TEXT)
RETURNS NUMERIC AS $$
DECLARE
  colon_count INT;
  ref_num INT;
  score NUMERIC;
BEGIN
  -- 1. Count ":" in network (fewer colons = higher priority)
  colon_count := length(COALESCE(network,'')) - length(replace(COALESCE(network,''), ':',''));

  -- 2. Parse numeric ref if possible
  BEGIN
    ref_num := NULLIF(regexp_replace(ref, '\D','','g'), '')::INT;
  EXCEPTION WHEN others THEN
    ref_num := 999999;
  END;
  IF ref_num IS NULL THEN
    ref_num := 999999;
  END IF;

  -- 3. Compute score as NUMERIC (safe for large values)
  score := (100 - colon_count) * 1000000000::NUMERIC
         + (1000000::NUMERIC - ref_num);

  RETURN score;
END;
$$ LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE;