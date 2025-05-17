CREATE OR REPLACE FUNCTION create_other_lines_mview(
    view_name TEXT
)
RETURNS void AS $$
DECLARE 
    sql_drop TEXT;
    sql_create TEXT;
    sql_index TEXT;
    sql_unique_index TEXT;
BEGIN
    RAISE NOTICE 'Creating materialized view: %', view_name;

    sql_drop := format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', view_name);
    EXECUTE sql_drop;

    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT DISTINCT ON (osm_id, type, member)
            geometry,
            id,
            osm_id,
            NULL::bigint AS member,
            name,
            class,
            type,
            start_date,
            end_date,
            'way' as source,
            tags
        FROM osm_other_lines

        UNION ALL

        SELECT DISTINCT ON (osm_id, type, member)
            geometry,
            id,
            osm_id,
            member,
            name,
            class,
            type,
            start_date,
            end_date,
            'relation' as source,
            tags
        FROM osm_other_relations_members
        WHERE osm_id NOT IN (
            SELECT osm_id FROM osm_other_areas
        )
    $sql$, view_name);
    EXECUTE sql_create;

    sql_index := format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', view_name, view_name);
    EXECUTE sql_index;

    sql_unique_index := format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id ON %I (osm_id, type, member);', view_name, view_name);
    EXECUTE sql_unique_index;

    RAISE NOTICE 'Materialized view % created successfully.', view_name;
END;
$$ LANGUAGE plpgsql;

SELECT create_other_lines_mview('mview_other_lines_z14_20');
