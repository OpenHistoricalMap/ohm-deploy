-- Create materialized views for other areas with different simplification levels
-- Using the generalized create_area_mview function

-- ============================================================================
-- Zoom 8-9:
-- Medium simplification (50m)
-- Medium areas (>1M m² = 1 km²)
-- ============================================================================
SELECT create_area_mview(
    source           => 'osm_other_areas',
    target           => 'mv_other_areas_z8_9',
    simplify_tol     => 100,
    min_metric       => 1000000,
    column_overrides => '{
        "religion": "NULLIF(tags->''religion'', '''')",
        "denomination": "NULLIF(tags->''denomination'', '''')"
    }'::jsonb
);
SELECT derive_centroid_mview(
    source           => 'mv_other_areas_z8_9',
    target           => 'mv_other_points_centroids_z8_9',
    only_named       => TRUE
);

-- ============================================================================
-- Zoom 10-12
-- ============================================================================
SELECT create_area_mview(
    source           => 'osm_other_areas',
    target           => 'mv_other_areas_z10_12',
    simplify_tol     => 20,
    min_metric       => 50000,
    column_overrides => '{
        "religion": "NULLIF(tags->''religion'', '''')",
        "denomination": "NULLIF(tags->''denomination'', '''')"
    }'::jsonb
);
SELECT derive_centroid_mview(
    source           => 'mv_other_areas_z10_12',
    target           => 'mv_other_points_centroids_z10_12',
    only_named       => TRUE
);

-- ============================================================================
-- Prepare points materialized view for higher zoom levels (12+)
-- ============================================================================
-- Prepare points table with necessary columns (start_decdate, end_decdate, area, etc.)
-- This must be done before creating centroids views that include points
SELECT create_point_mview(
    source           => 'osm_other_points',
    target           => 'mv_other_points',
    column_overrides => '{
        "religion": "NULLIF(tags->''religion'', '''')",
        "denomination": "NULLIF(tags->''denomination'', '''')"
    }'::jsonb
);


-- ============================================================================
-- Zoom 13-15:
-- ============================================================================
SELECT create_area_mview(
    source           => 'osm_other_areas',
    target           => 'mv_other_areas_z13_15',
    simplify_tol     => 5,
    min_metric       => 5000,
    column_overrides => '{
        "religion": "NULLIF(tags->''religion'', '''')",
        "denomination": "NULLIF(tags->''denomination'', '''')"
    }'::jsonb
);
SELECT derive_centroid_mview(
    source           => 'mv_other_areas_z13_15',
    target           => 'mv_other_points_centroids_z13_15',
    union_source     => 'mv_other_points',
    only_named       => TRUE
);

-- ============================================================================
-- Zoom 16-20:
-- No simplification
-- All areas
-- Include other points
-- ============================================================================
SELECT create_area_mview(
    source           => 'osm_other_areas',
    target           => 'mv_other_areas_z16_20',
    column_overrides => '{
        "religion": "NULLIF(tags->''religion'', '''')",
        "denomination": "NULLIF(tags->''denomination'', '''')"
    }'::jsonb
);
SELECT derive_centroid_mview(
    source           => 'mv_other_areas_z16_20',
    target           => 'mv_other_points_centroids_z16_20',
    union_source     => 'mv_other_points',
    only_named       => TRUE
);

-- ============================================================================
-- Materialized view: mv_other_lines_z16_20
-- Description:
--   Merges other lines from:
--     - osm_other_lines      (ways: barrier=*, man_made=*, historic=*, power=*, military=*),
--     - osm_other_multilines (relation members: same tags on the relation,
--                             e.g. type=multilinestring city walls or pipelines).
--
--   A way that belongs to a matching relation is rendered from the relation
--   row: relation tags are the base, but the member way's own start_date,
--   end_date and name override them when set (a wall segment rebuilt later
--   keeps its own dates). Ways with no matching relation render as-is.
--
--   Each row gets a source_type ('way' or 'relation') and a relation column
--   (relation osm_id, NULL for plain ways). Multilingual name columns are added.
-- ============================================================================
DO $do$
DECLARE
  lang_columns TEXT := get_language_columns();
  sql_create TEXT;
BEGIN
  sql_create := format($sql$
    CREATE MATERIALIZED VIEW mv_other_lines_z16_20_tmp AS
    WITH members AS (
      SELECT
        m.id,
        ABS(m.member::bigint) AS osm_id,
        ABS(m.osm_id) AS relation,
        m.geometry,
        COALESCE(NULLIF(m.name, ''), NULLIF(m.me_name, '')) AS name,
        m.type,
        m.class,
        COALESCE(NULLIF(m.me_start_date, ''), NULLIF(m.start_date, '')) AS start_date,
        COALESCE(NULLIF(m.me_end_date, ''), NULLIF(m.end_date, '')) AS end_date,
        (COALESCE(m.me_tags, ''::hstore) || m.tags) AS tags
      FROM osm_other_multilines AS m
      WHERE m.geometry IS NOT NULL
        AND ST_GeometryType(m.geometry) IN ('ST_LineString', 'ST_MultiLineString')
    )
    -- Plain ways: not a member of any matching relation
    SELECT
      l.id,
      l.osm_id,
      NULL::bigint AS relation,
      l.geometry,
      NULLIF(l.name, '') AS name,
      l.type,
      l.class,
      NULLIF(l.start_date, '') AS start_date,
      NULLIF(l.end_date, '') AS end_date,
      isodatetodecimaldate(pad_date(l.start_date, 'start'), FALSE) AS start_decdate,
      isodatetodecimaldate(pad_date(l.end_date, 'end'), FALSE) AS end_decdate,
      l.tags,
      'way' AS source_type,
      %s
    FROM osm_other_lines AS l
    WHERE l.geometry IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM members AS mm WHERE mm.osm_id = l.osm_id)

    UNION ALL

    -- Relation members: relation tags, member way dates/name on top
    SELECT
      id,
      osm_id,
      relation,
      geometry,
      name,
      type,
      class,
      start_date,
      end_date,
      isodatetodecimaldate(pad_date(start_date, 'start'), FALSE) AS start_decdate,
      isodatetodecimaldate(pad_date(end_date, 'end'), FALSE) AS end_decdate,
      tags,
      'relation' AS source_type,
      %s
    FROM members
  $sql$, lang_columns, lang_columns);

  PERFORM finalize_materialized_view(
    'mv_other_lines_z16_20_tmp',
    'mv_other_lines_z16_20',
    'id, osm_id, source_type',
    sql_create
  );
END $do$;

SELECT derive_line_mview(
    source           => 'mv_other_lines_z16_20',
    target           => 'mv_other_lines_z14_15',
    simplify_tol     => 5,
    unique_columns   => ARRAY['id', 'osm_id', 'source_type']
);
-- Refresh areas views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_areas_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_areas_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_areas_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_areas_z16_20;

-- Refresh centroids views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_points_centroids_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_points_centroids_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_points_centroids_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_points_centroids_z16_20;

-- Refresh lines views
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_lines_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_other_lines_z14_15;
