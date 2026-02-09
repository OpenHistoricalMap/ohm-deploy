-- Function source for Martin: returns bytea MVT tiles
-- Routes to the correct materialized view based on zoom level
-- Source-layer name in MVT: "transport_areas"
DROP FUNCTION IF EXISTS public.transport_areas(integer, integer, integer, json);

CREATE OR REPLACE FUNCTION public.transport_areas(
    z integer,
    x integer,
    y integer,
    query_params json DEFAULT '{}'::json
) RETURNS bytea AS $$
DECLARE
    bounds geometry := ST_TileEnvelope(z, x, y);
    mvt bytea;
    table_name text;
    cols_no_geom text;
BEGIN
    -- Select the appropriate materialized view based on zoom level
    IF z <= 12 THEN
        table_name := 'mv_transport_areas_z10_12';
    ELSIF z <= 15 THEN
        table_name := 'mv_transport_areas_z13_15';
    ELSE
        table_name := 'mv_transport_areas_z16_20';
    END IF;

    -- Get all columns except 'geometry' (pg_attribute is always in shared buffers, ~microseconds)
    SELECT string_agg(quote_ident(attname), ', ' ORDER BY attnum)
    INTO cols_no_geom
    FROM pg_attribute a
    JOIN pg_class c ON a.attrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND c.relname = table_name
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND attname NOT IN ('geometry', 'tags');

    -- Build and execute dynamic query with all columns + MVT geometry
    EXECUTE format(
        'SELECT ST_AsMVT(q, ''transport_areas'') FROM (
            SELECT %s, ST_AsMVTGeom(t.geometry, $1) AS geometry
            FROM public.%I t
            WHERE t.geometry && $1
        ) q',
        cols_no_geom,
        table_name
    ) INTO mvt USING bounds;

    RETURN mvt;
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE;
