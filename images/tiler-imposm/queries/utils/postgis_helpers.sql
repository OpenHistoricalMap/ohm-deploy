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

-- Parse free-form OSM/OHM height-like values (height=*, min_height=*, roof:height=*,
-- building:height=*) to meters as double precision.
--
-- Accepts (canonical units per https://wiki.openstreetmap.org/wiki/Map_features/Units):
--   "20", "20.5"            -> meters (OSM default unit)
--   "20 m", "20m"           -> meters with explicit unit (case-sensitive)
--   "85'"                   -> feet -> meters
--   "8'5\"", "8'5"          -> feet + inches -> meters
--   "8 1/2'"                -> fractional feet (US notation) -> meters
--
-- Hardening:
--   - Normalizes Unicode curly quotes/primes to ASCII straight quotes
--     (’ -> ', ” -> ", ′ -> ', ″ -> ") and NBSP to space.
--   - Collapses whitespace runs (tabs, newlines, multiple spaces) before parsing.
--   - Rejects strings longer than 64 chars early (likely garbage / URLs).
--   - Regex pre-validates before any cast, so the function never raises and
--     no EXCEPTION block is needed (avoids per-call subtransaction overhead
--     in bulk queries).
--
-- Returns NULL for null / empty / unparseable / non-positive / >1000m input.
-- Why NULL on 0: 0 in MVT short-circuits style COALESCE chains and renders
-- 3D extrusions flat. NULL is stripped from MVT properties, so consumers can
-- use ["coalesce", ["get","height"], <fallback>] as intended.
CREATE OR REPLACE FUNCTION parse_to_meters(input text) RETURNS double precision AS $$
DECLARE
    s        text;
    ft       numeric;
    ft_int   numeric;
    ft_num   numeric;
    ft_den   numeric;
    inch     numeric;
    result   double precision;
BEGIN
    IF input IS NULL THEN
        RETURN NULL;
    END IF;

    -- Normalize Unicode quotes/primes to ASCII; map NBSP to space.
    s := translate(input,
        E'‘’‛′“”‟″ ',
        '''''''''""""' || ' ');
    -- Collapse whitespace runs and trim.
    s := btrim(regexp_replace(s, '\s+', ' ', 'g'));

    IF s = '' OR length(s) > 64 THEN
        RETURN NULL;
    END IF;

    -- Fractional feet (US notation):  8 1/2'  ->  8.5'
    IF s ~ '^\d+ \d+/\d+''$' THEN
        ft_int := (regexp_match(s, '^(\d+) '))[1]::numeric;
        ft_num := (regexp_match(s, ' (\d+)/'))[1]::numeric;
        ft_den := (regexp_match(s, '/(\d+)'''))[1]::numeric;
        IF ft_den = 0 THEN
            RETURN NULL;
        END IF;
        result := (ft_int + ft_num / ft_den) * 0.3048;

    -- Feet + optional inches:  8'5"  /  8'5  /  8'
    ELSIF s ~ '^\d+(\.\d+)?''( ?\d+(\.\d+)?"?)?$' THEN
        ft   := (regexp_match(s, '^(\d+(\.\d+)?)'''))[1]::numeric;
        inch := COALESCE((regexp_match(s, ''' ?(\d+(\.\d+)?)"?$'))[1], '0')::numeric;
        result := (ft * 0.3048) + (inch * 0.0254);

    -- Meters (default or with explicit "m" suffix).
    -- Symbols case-sensitive per OSM Units spec.
    ELSIF s ~ '^-?\d+(\.\d+)?( ?m)?$' THEN
        result := regexp_replace(s, ' ?m$', '')::double precision;

    ELSE
        RETURN NULL;
    END IF;

    IF result IS NULL OR result <= 0 OR result > 1000 THEN
        RETURN NULL;
    END IF;
    RETURN result;
END;
$$ STRICT
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE;

-- Parse a numeric string to numeric, or NULL if malformed.
-- Regex from OpenMapTiles CleanNumeric.
CREATE OR REPLACE FUNCTION clean_numeric(input text) RETURNS numeric AS $$
    SELECT substring(input from '^\s*([-+]?(?=\d|\.\d)\d*(?:\.\d*)?(?:[Ee][-+]?\d+)?)\s*$')::numeric;
$$ STRICT
LANGUAGE sql IMMUTABLE PARALLEL SAFE;

-- Resolve a building height in meters, using OpenMapTiles fallback order:
--   1. height=*               (parsed via parse_to_meters)
--   2. building:height=*      (deprecated alias, parsed)
--   3. building:levels=* * 3m (one level assumed 3m)
-- Returns NULL when no source is parseable. Mirrors the openmaptiles
-- building layer logic so render_height stays consistent across consumers.
-- Reference (OMT uses 3.66m per level; we use 3m):
--   https://github.com/openmaptiles/openmaptiles/blob/master/layers/building/building.sql#L101-L102
CREATE OR REPLACE FUNCTION render_height(
    height_text          text,
    building_height_text text,
    building_levels_text text
) RETURNS double precision AS $$
    SELECT COALESCE(
        public.parse_to_meters(height_text),
        public.parse_to_meters(building_height_text),
        public.clean_numeric(building_levels_text)::double precision * 3
    );
$$ LANGUAGE sql IMMUTABLE PARALLEL SAFE;

-- Resolve a building min_height in meters using the same fallback pattern:
--   1. min_height=*               (parsed via parse_to_meters)
--   2. building:min_level=* * 3m  (one level assumed 3m)
CREATE OR REPLACE FUNCTION render_min_height(
    min_height_text        text,
    building_min_level_text text
) RETURNS double precision AS $$
    SELECT COALESCE(
        public.parse_to_meters(min_height_text),
        public.clean_numeric(building_min_level_text)::double precision * 3
    );
$$ LANGUAGE sql IMMUTABLE PARALLEL SAFE;

COMMIT;