/*
    helper functions that should be installed alongside the OSM import
*/

BEGIN;

 -- Inspired by http://stackoverflow.com/questions/16195986/isnumeric-with-postgresql/16206123#16206123
CREATE OR REPLACE FUNCTION as_numeric(text) RETURNS NUMERIC AS $$
DECLARE test NUMERIC;
BEGIN
     test = $1::NUMERIC;
     RETURN test;
EXCEPTION WHEN others THEN
     RETURN -1;
END;
$$ STRICT
LANGUAGE plpgsql IMMUTABLE;

-- Parse free-form OSM height-like values to meters as double precision.
-- Accepts: "20", "20.5", "20 m", "20m", "20 meters" (case-insensitive).
-- Returns NULL for null/empty/unparseable input or for non-positive / out-of-range
-- values (<=0 or >1000m). NULLs are stripped from MVT properties, so consumers
-- can use ["coalesce", ["get","height"], <fallback>] safely. Why: a 0 is a real
-- numeric in MVT and would short-circuit coalesce, rendering 3D extrusions flat.
CREATE OR REPLACE FUNCTION parse_to_meters(input text) RETURNS double precision AS $$
DECLARE
    cleaned text;
    result  double precision;
BEGIN
    IF trim(input) = '' THEN
        RETURN NULL;
    END IF;
    cleaned := regexp_replace(trim(input), '\s*(m|meter|meters)\s*$', '', 'i');
    IF cleaned !~ '^-?\d+(\.\d+)?$' THEN
        RETURN NULL;
    END IF;
    result := cleaned::double precision;
    IF result <= 0 OR result > 1000 THEN
        RETURN NULL;
    END IF;
    RETURN result;
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$ STRICT
LANGUAGE plpgsql IMMUTABLE;

COMMIT;