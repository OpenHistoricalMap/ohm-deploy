-- From:https://github.com/OpenHistoricalMap/issues/issues/940
-- This query creates a materialized view for building points and buildings centroids
CREATE OR REPLACE FUNCTION create_buildings_materialized_view(
    min_area DOUBLE PRECISION, --area in m2
    view_name TEXT
) RETURNS VOID AS
$$
DECLARE
    sql TEXT;
BEGIN
    RAISE NOTICE 'Dropping materialized view %', view_name;
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);

    RAISE NOTICE 'Creating materialized view %', view_name;
    sql := format(
        $f$
        CREATE MATERIALIZED VIEW %I AS
        SELECT
            osm_id,
            geometry,
            name,
            NULL AS height,
            NULL AS area,
            type,
            start_date,
            end_date,
            'point' AS source,
            tags
        FROM
            osm_buildings_points_named

        UNION ALL

        SELECT
            osm_id,
            (ST_MaximumInscribedCircle(geometry)).center AS geometry,
            name,
            NULLIF(as_numeric(height), -1) AS height,
            ST_Area(geometry) AS area,
            type,
            start_date,
            end_date,
            'centroid' AS source,
            tags
        FROM
            osm_buildings
        WHERE
            name IS NOT NULL
            AND name <> ''
            AND ST_Area(geometry) >= %L;
        $f$,
        view_name,
        min_area
    );

    EXECUTE sql;

    RAISE NOTICE 'Creating indexes on %', view_name;
    EXECUTE format('CREATE UNIQUE INDEX %I_uidx ON %I (osm_id, source);', view_name, view_name);
    EXECUTE format('CREATE INDEX %I_geom_idx ON %I USING GIST (geometry);', view_name, view_name);

    RAISE NOTICE 'Materialized view % created successfully', view_name;
END;
$$ LANGUAGE plpgsql;

SELECT create_buildings_materialized_view(1500, 'mview_buildings_points_centroids_z14');
SELECT create_buildings_materialized_view(1000, 'mview_buildings_points_centroids_z15');
SELECT create_buildings_materialized_view(0, 'mview_buildings_points_centroids_z16_20');
