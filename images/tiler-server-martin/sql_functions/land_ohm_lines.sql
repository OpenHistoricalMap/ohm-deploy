-- Function source for Martin: returns bytea MVT tiles
-- Routes to the correct materialized view based on zoom level
-- Source-layer name in MVT: "land_ohm_lines"
DROP FUNCTION IF EXISTS public.land_ohm_lines(integer, integer, integer, json);

CREATE OR REPLACE FUNCTION public.land_ohm_lines(
    z integer,
    x integer,
    y integer,
    query_params json DEFAULT '{}'::json
) RETURNS bytea AS $$
DECLARE
    bounds geometry := ST_TileEnvelope(z, x, y);
    mvt bytea;
BEGIN
    IF z <= 2 THEN
        SELECT ST_AsMVT(q, 'land_ohm_lines') INTO mvt FROM (
            SELECT t.osm_id, t.admin_level, t.type,
                   t.start_date, t.end_date, t.start_decdate, t.end_decdate,
                   ST_AsMVTGeom(t.geometry, bounds) AS geometry
            FROM public.mv_admin_boundaries_lines_z0_2 t
            WHERE t.geometry && bounds
        ) q;
    ELSIF z <= 5 THEN
        SELECT ST_AsMVT(q, 'land_ohm_lines') INTO mvt FROM (
            SELECT t.osm_id, t.admin_level, t.type,
                   t.start_date, t.end_date, t.start_decdate, t.end_decdate,
                   ST_AsMVTGeom(t.geometry, bounds) AS geometry
            FROM public.mv_admin_boundaries_lines_z3_5 t
            WHERE t.geometry && bounds
        ) q;
    ELSIF z <= 7 THEN
        SELECT ST_AsMVT(q, 'land_ohm_lines') INTO mvt FROM (
            SELECT t.osm_id, t.admin_level, t.type,
                   t.start_date, t.end_date, t.start_decdate, t.end_decdate,
                   ST_AsMVTGeom(t.geometry, bounds) AS geometry
            FROM public.mv_admin_boundaries_lines_z6_7 t
            WHERE t.geometry && bounds
        ) q;
    ELSIF z <= 9 THEN
        SELECT ST_AsMVT(q, 'land_ohm_lines') INTO mvt FROM (
            SELECT t.osm_id, t.admin_level, t.type,
                   t.start_date, t.end_date, t.start_decdate, t.end_decdate,
                   ST_AsMVTGeom(t.geometry, bounds) AS geometry
            FROM public.mv_admin_boundaries_lines_z8_9 t
            WHERE t.geometry && bounds
        ) q;
    ELSIF z <= 12 THEN
        SELECT ST_AsMVT(q, 'land_ohm_lines') INTO mvt FROM (
            SELECT t.osm_id, t.admin_level, t.type,
                   t.start_date, t.end_date, t.start_decdate, t.end_decdate,
                   ST_AsMVTGeom(t.geometry, bounds) AS geometry
            FROM public.mv_admin_boundaries_lines_z10_12 t
            WHERE t.geometry && bounds
        ) q;
    ELSIF z <= 15 THEN
        SELECT ST_AsMVT(q, 'land_ohm_lines') INTO mvt FROM (
            SELECT t.osm_id, t.admin_level, t.type,
                   t.start_date, t.end_date, t.start_decdate, t.end_decdate,
                   ST_AsMVTGeom(t.geometry, bounds) AS geometry
            FROM public.mv_admin_boundaries_lines_z13_15 t
            WHERE t.geometry && bounds
        ) q;
    ELSE
        SELECT ST_AsMVT(q, 'land_ohm_lines') INTO mvt FROM (
            SELECT t.osm_id, t.admin_level, t.type,
                   t.start_date, t.end_date, t.start_decdate, t.end_decdate,
                   ST_AsMVTGeom(t.geometry, bounds) AS geometry
            FROM public.mv_admin_boundaries_lines_z16_20 t
            WHERE t.geometry && bounds
        ) q;
    END IF;

    RETURN mvt;
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE;
