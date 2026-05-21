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

-- Parse free-form OSM height-like values (height=*, min_height=*, roof:height=*,
-- building:height=*) to meters as double precision.
--
-- Accepts (per https://wiki.openstreetmap.org/wiki/Key:height):
--   "20", "20.5"            -> meters (OSM default unit)
--   "20 m", "20m"           -> meters with explicit unit
--   "20 meter", "20 meters"
--   "85'", "85 ft"          -> feet -> meters
--   "8'5\"", "8'5"          -> feet + inches -> meters
--
-- Returns NULL for null/empty/unparseable input or for non-positive / out-of-range
-- values (<=0 or >1000m). NULLs are stripped from MVT properties, so consumers
-- can use ["coalesce", ["get","height"], <fallback>] safely. Why: a 0 is a real
-- numeric in MVT and would short-circuit coalesce, rendering 3D extrusions flat.
CREATE OR REPLACE FUNCTION parse_to_meters(input text) RETURNS double precision AS $$
DECLARE
    s        text;
    ft       numeric;
    inch     numeric;
    m        text;
    result   double precision;
BEGIN
    s := trim(input);
    IF s = '' THEN
        RETURN NULL;
    END IF;

    -- feet + optional inches:  8'5"  /  8'5  /  8'
    IF s ~ '^\d+(\.\d+)?''(\s*\d+(\.\d+)?"?)?$' THEN
        ft   := (regexp_match(s, '^(\d+(\.\d+)?)'''))[1]::numeric;
        inch := COALESCE((regexp_match(s, '''\s*(\d+(\.\d+)?)"?$'))[1], '0')::numeric;
        result := (ft * 0.3048) + (inch * 0.0254);
    -- feet with ft suffix:  85ft  /  85 ft  /  85.5 ft
    ELSIF s ~* '^\d+(\.\d+)?\s*ft$' THEN
        ft := regexp_replace(s, '\s*ft$', '', 'i')::numeric;
        result := ft * 0.3048;
    -- meters (default or explicit):  20  /  20.5  /  20 m  /  20m  /  20 meters
    ELSIF s ~* '^-?\d+(\.\d+)?\s*(m|meter|meters)?$' THEN
        m := regexp_replace(s, '\s*(m|meter|meters)\s*$', '', 'i');
        result := m::double precision;
    ELSE
        RETURN NULL;
    END IF;

    IF result <= 0 OR result > 1000 THEN
        RETURN NULL;
    END IF;
    RETURN result;
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$ STRICT
LANGUAGE plpgsql IMMUTABLE;

-- Parse a numeric string to numeric, or NULL if malformed.
-- Regex from OpenMapTiles CleanNumeric.
CREATE OR REPLACE FUNCTION clean_numeric(input text) RETURNS numeric AS $$
    SELECT substring(input from '^\s*([-+]?(?=\d|\.\d)\d*(?:\.\d*)?(?:[Ee][-+]?\d+)?)\s*$')::numeric;
$$ STRICT
LANGUAGE sql IMMUTABLE PARALLEL SAFE;

COMMIT;