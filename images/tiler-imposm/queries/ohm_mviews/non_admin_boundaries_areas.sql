-- ============================================================================
-- Create materialized  views for non-admin boundaries areas https://github.com/OpenHistoricalMap/issues/issues/1251
-- ============================================================================

-- Keeps the view from scanning the admin members on every refresh.
-- A failed build leaves an invalid index that IF NOT EXISTS would keep, so drop it first.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'osm_admin_relation_members_non_admin_member_idx'
      AND NOT i.indisvalid
  ) THEN
    DROP INDEX osm_admin_relation_members_non_admin_member_idx;
  END IF;
END $$;

-- CONCURRENTLY does not block imposm, it only waits for its open transaction to end.
-- lock_timeout would cancel that wait and leave the index invalid.
SET lock_timeout = 0;
CREATE INDEX CONCURRENTLY IF NOT EXISTS osm_admin_relation_members_non_admin_member_idx
ON osm_admin_relation_members (member)
WHERE type <> 'administrative';
RESET lock_timeout;

-- ============================================================================
-- Source view: polygons plus the boundaries that imposm could not close
-- https://github.com/OpenHistoricalMap/issues/issues/1301
--   - polygon: closed ways and complete relations from osm_admin_areas
--   - line: relations without a polygon (one row per relation, member ways merged)
--           and open ways that are not part of a relation
-- Columns follow osm_admin_areas, so lines and polygons share the same layer.
-- ============================================================================
CREATE OR REPLACE VIEW osm_non_admin_boundaries AS
SELECT
    id, osm_id, name, type, admin_level, has_label, start_date, end_date, area,
    border_type, indefinite, disputed, disputed_by, tags, geometry
FROM osm_admin_areas
WHERE type <> 'administrative'

UNION ALL

SELECT
    MIN(m.id) AS id,
    m.osm_id,
    m.name,
    m.type,
    m.admin_level,
    0::smallint AS has_label,
    m.start_date,
    m.end_date,
    NULL::real AS area,
    (m.tags->'border_type')::varchar AS border_type,
    (m.tags->'indefinite')::varchar AS indefinite,
    (m.tags->'disputed')::varchar AS disputed,
    (m.tags->'disputed_by')::varchar AS disputed_by,
    m.tags,
    ST_LineMerge(ST_Collect(m.geometry)) AS geometry
FROM osm_admin_relation_members m
WHERE m.type <> 'administrative'
  AND ST_GeometryType(m.geometry) = 'ST_LineString'
  AND NOT EXISTS (SELECT 1 FROM osm_admin_areas a WHERE a.osm_id = m.osm_id)
GROUP BY m.osm_id, m.name, m.type, m.admin_level, m.start_date, m.end_date, m.tags

UNION ALL

SELECT
    l.id,
    l.osm_id,
    l.name,
    l.type,
    l.admin_level,
    l.has_label,
    l.start_date,
    l.end_date,
    NULL::real AS area,
    (l.tags->'border_type')::varchar AS border_type,
    l.indefinite,
    l.disputed,
    l.disputed_by,
    l.tags,
    l.geometry
FROM osm_admin_lines l
WHERE l.type <> 'administrative'
  AND NOT EXISTS (SELECT 1 FROM osm_admin_areas a WHERE a.osm_id = l.osm_id)
  AND NOT EXISTS (
      SELECT 1 FROM osm_admin_relation_members m
      WHERE m.member = l.osm_id AND m.type <> 'administrative'
  );

SELECT create_area_mview(
    source           => 'osm_non_admin_boundaries',
    target           => 'mv_non_admin_boundaries_areas_z16_20',
    simplify_tol     => 1,
    column_overrides => '{
        "religion": "tags->''religion''",
        "denomination": "tags->''denomination''",
        "timezone": "tags->''timezone''",
        "utc": "tags->''utc''",
        "postal_code": "tags->''postal_code''",
        "ref": "tags->''ref''",
        "political_division": "tags->''political_division''"
    }'::jsonb
);
SELECT derive_area_mview(
    source           => 'mv_non_admin_boundaries_areas_z16_20',
    target           => 'mv_non_admin_boundaries_areas_z13_15',
    simplify_tol     => 5
);
SELECT derive_area_mview(
    source           => 'mv_non_admin_boundaries_areas_z13_15',
    target           => 'mv_non_admin_boundaries_areas_z10_12',
    simplify_tol     => 20
);
SELECT derive_area_mview(
    source           => 'mv_non_admin_boundaries_areas_z10_12',
    target           => 'mv_non_admin_boundaries_areas_z8_9',
    simplify_tol     => 100
);
SELECT derive_area_mview(
    source           => 'mv_non_admin_boundaries_areas_z8_9',
    target           => 'mv_non_admin_boundaries_areas_z6_7',
    simplify_tol     => 200
);
SELECT derive_area_mview(
    source           => 'mv_non_admin_boundaries_areas_z6_7',
    target           => 'mv_non_admin_boundaries_areas_z3_5',
    simplify_tol     => 1000
);
SELECT derive_area_mview(
    source           => 'mv_non_admin_boundaries_areas_z3_5',
    target           => 'mv_non_admin_boundaries_areas_z0_2',
    simplify_tol     => 5000
);
-- ============================================================================
-- Centroids views for non-admin boundaries areas
-- ============================================================================

SELECT derive_centroid_mview(
    source           => 'mv_non_admin_boundaries_areas_z16_20',
    target           => 'mv_non_admin_boundaries_centroids_z16_20',
    only_named       => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_non_admin_boundaries_areas_z13_15',
    target           => 'mv_non_admin_boundaries_centroids_z13_15',
    only_named       => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_non_admin_boundaries_areas_z10_12',
    target           => 'mv_non_admin_boundaries_centroids_z10_12',
    only_named       => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_non_admin_boundaries_areas_z8_9',
    target           => 'mv_non_admin_boundaries_centroids_z8_9',
    only_named       => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_non_admin_boundaries_areas_z6_7',
    target           => 'mv_non_admin_boundaries_centroids_z6_7',
    only_named       => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_non_admin_boundaries_areas_z3_5',
    target           => 'mv_non_admin_boundaries_centroids_z3_5',
    only_named       => TRUE
);
SELECT derive_centroid_mview(
    source           => 'mv_non_admin_boundaries_areas_z0_2',
    target           => 'mv_non_admin_boundaries_centroids_z0_2',
    only_named       => TRUE
);
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z3_5;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_areas_z0_2;

-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z16_20;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z13_15;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z10_12;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z8_9;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z6_7;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z3_5;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_admin_boundaries_centroids_z0_2;
