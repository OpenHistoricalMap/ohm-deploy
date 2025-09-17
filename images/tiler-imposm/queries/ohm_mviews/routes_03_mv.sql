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
          way_id,
          min_start_decdate, max_end_decdate,
          min_start_date_iso, max_end_date_iso,
          CASE 
            WHEN %s > 0 THEN ST_Simplify(geometry, %s) 
            ELSE geometry 
          END AS geometry,
          num_routes,
          route_1_ref, route_1_network, route_1_operator, route_1_type, route_1_name,
          route_2_ref, route_2_network, route_2_operator, route_2_type, route_2_name,
          route_3_ref, route_3_network, route_3_operator, route_3_type, route_3_name,
          route_4_ref, route_4_network, route_4_operator, route_4_type, route_4_name,
          route_5_ref, route_5_network, route_5_operator, route_5_type, route_5_name,
          route_6_ref, route_6_network, route_6_operator, route_6_type, route_6_name,
          routes
        FROM mv_routes_indexed
        WHERE ST_Length(geometry) > %s
        WITH DATA;

        -- Create unique index (required for concurrent refresh)
        CREATE UNIQUE INDEX %I_way_id_idx
          ON %I (way_id, min_start_decdate, max_end_decdate, route_1_ref, route_2_ref, route_3_ref);

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

-- ============================================================================
-- Create materialized views for routes by length ranges
-- ============================================================================

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
