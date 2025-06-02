-- ============================================================================
-- Function: create_or_refresh_transport_associated_streets_lines_mview
-- Description:
--   Creates or refreshes a materialized view for relation-based geometries,
--   using `ST_AsMVTGeom` for tile rendering and language columns prefixed with 'r.'.
--
-- Parameters:
--   input_table       TEXT    - Base table for the relation (alias 'r')
--   member_table      TEXT    - Table with relation members (alias 'm')
--   mview_name        TEXT    - Name of the materialized view to be created
--   force_create      BOOLEAN - If TRUE, always recreate the view
--
-- Notes:
--   - Requires function `get_language_columns(prefix TEXT)`
--   - Automatically adds GiST spatial index and unique index on (r.id, m.index)
-- ============================================================================

DROP FUNCTION IF EXISTS create_or_refresh_transport_associated_streets_lines_mview;
CREATE OR REPLACE FUNCTION create_or_refresh_transport_associated_streets_lines_mview(
  input_table TEXT,
  member_table TEXT,
  mview_name TEXT,
  force_create BOOLEAN DEFAULT FALSE
)
RETURNS void AS $$
DECLARE
  lang_columns TEXT;
  sql TEXT;
BEGIN
  -- Check whether to recreate or refresh
  IF NOT force_create AND NOT recreate_or_refresh_view(mview_name) THEN
      RETURN;
  END IF;

  RAISE NOTICE 'Creating relation-based materialized view: %', mview_name;

  -- Get dynamic language columns prefixed with 'r.'
  lang_columns := get_language_columns('r.');

  -- Drop old view
  EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', mview_name);

  -- Build and create materialized view
  sql := format($sql$
    CREATE MATERIALIZED VIEW %I AS
    SELECT 
      ST_AsMVTGeom(r.geometry, '!BBOX!') AS geometry, 
      m.member, 
      r.osm_id AS osm_id, 
      m.name AS name, 
      m.relname AS relname, 
      m.index AS index, 
      r.type AS type, 
      r.tags->'start_date' AS start_date, 
      r.tags->'end_date' AS end_date, 
      isodatetodecimaldate(pad_date(r.tags->'start_date', 'start')) AS start_decdate, 
      isodatetodecimaldate(pad_date(r.tags->'end_date', 'end')) AS end_decdate,
      %s
    FROM %I r
    JOIN %I m ON m.osm_id = r.osm_id
    WHERE r.geometry IS NOT NULL;
  $sql$, mview_name, lang_columns, input_table, member_table);

  EXECUTE sql;

  -- Add spatial index
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_geom ON %I USING GIST (geometry);', mview_name, mview_name);

  -- Add unique index on id and member index
  EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%I_id_member ON %I (id, index);', mview_name, mview_name);

  RAISE NOTICE 'Materialized view % created successfully.', mview_name;
END;
$$ LANGUAGE plpgsql;

SELECT create_or_refresh_transport_associated_streets_lines_mview(
  'osm_relations',     -- input_table (r)
  'osm_relation_members',    -- member_table (m)
  'mv_route_lines',          -- mview_name
  TRUE                       -- force_create
);