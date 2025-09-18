CREATE OR REPLACE FUNCTION create_mv_routes_by_length(
    full_view_name TEXT,
    min_length DOUBLE PRECISION,
    simplify_tol DOUBLE PRECISION
) RETURNS void AS $$
BEGIN
    EXECUTE format(
        $f$
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
          num_routes,
          NULLIF(route_1_ref, '') AS route_1_ref,
          NULLIF(route_1_network, '') AS route_1_network,
          NULLIF(route_1_operator, '') AS route_1_operator,
          NULLIF(route_1_type, '') AS route_1_type,
          NULLIF(route_1_name, '') AS route_1_name,
          NULLIF(route_2_ref, '') AS route_2_ref,
          NULLIF(route_2_network, '') AS route_2_network,
          NULLIF(route_2_operator, '') AS route_2_operator,
          NULLIF(route_2_type, '') AS route_2_type,
          NULLIF(route_2_name, '') AS route_2_name,
          NULLIF(route_3_ref, '') AS route_3_ref,
          NULLIF(route_3_network, '') AS route_3_network,
          NULLIF(route_3_operator, '') AS route_3_operator,
          NULLIF(route_3_type, '') AS route_3_type,
          NULLIF(route_3_name, '') AS route_3_name,
          NULLIF(route_4_ref, '') AS route_4_ref,
          NULLIF(route_4_network, '') AS route_4_network,
          NULLIF(route_4_operator, '') AS route_4_operator,
          NULLIF(route_4_type, '') AS route_4_type,
          NULLIF(route_4_name, '') AS route_4_name,
          NULLIF(route_5_ref, '') AS route_5_ref,
          NULLIF(route_5_network, '') AS route_5_network,
          NULLIF(route_5_operator, '') AS route_5_operator,
          NULLIF(route_5_type, '') AS route_5_type,
          NULLIF(route_5_name, '') AS route_5_name,
          NULLIF(route_6_ref, '') AS route_6_ref,
          NULLIF(route_6_network, '') AS route_6_network,
          NULLIF(route_6_operator, '') AS route_6_operator,
          NULLIF(route_6_type, '') AS route_6_type,
          NULLIF(route_6_name, '') AS route_6_name,
          routes
        FROM mv_routes_indexed
        WHERE ST_Length(geometry) > %s
        WITH DATA;

        -- Create unique index (required for concurrent refresh)
        CREATE UNIQUE INDEX %I_way_id_idx
          ON %I (osm_id, start_decdate, end_decdate, route_1_ref, route_2_ref, route_3_ref);

        -- Create spatial index
        CREATE INDEX %I_geom_idx
          ON %I USING GIST (geometry);
        $f$,
        full_view_name, full_view_name,
        simplify_tol, simplify_tol,
        min_length,
        full_view_name, full_view_name,  -- unique index
        full_view_name, full_view_name   -- spatial index
    );
END;
$$ LANGUAGE plpgsql;

SELECT create_mv_routes_by_length('mv_routes_indexed_z5_6', 10000, 500);
SELECT create_mv_routes_by_length('mv_routes_indexed_z7_8', 5000, 300);
SELECT create_mv_routes_by_length('mv_routes_indexed_z9_10', 1500, 150);
SELECT create_mv_routes_by_length('mv_routes_indexed_z11_13', 500, 50);
SELECT create_mv_routes_by_length('mv_routes_indexed_z14_20', 0, 10);


-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_routes_indexed_z5_6;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_routes_indexed_z7_8;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_routes_indexed_z9_10;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_routes_indexed_z11_13;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_routes_indexed_z14_20;
