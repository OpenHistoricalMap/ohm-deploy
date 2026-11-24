-- ============================================================================
-- Non-admin boundary lines for the land_ohm_lines layer
-- https://github.com/OpenHistoricalMap/issues/issues/1442
--
-- Same treatment as admin_boundaries_lines.sql, for every boundary=* value that
-- is not "administrative": one line per way, per type and per time period.
-- The admin views are not changed. The land_ohm_lines_z* views at the end join
-- the admin and the non-admin lines for the tiles.
-- ============================================================================

-- ============================================================================
-- STEP 1: Lines at zoom 16-20
--   relation_lines: member ways of the relations. Rows of the same way, type and
--                   admin_level with no gap between their dates become one line.
--   way_lines:      ways tagged boundary=* that are not members of a relation
--                   of the same type.
-- The decimal dates are computed here: the stored start_decdate and end_decdate
-- are only backfilled for administrative rows.
-- ============================================================================
SELECT finalize_materialized_view(
    'mv_non_admin_boundaries_lines_z16_20_tmp',
    'mv_non_admin_boundaries_lines_z16_20',
    'id',
    $sql$
    CREATE MATERIALIZED VIEW mv_non_admin_boundaries_lines_z16_20_tmp AS
    WITH members AS (
      SELECT
        type,
        admin_level,
        member,
        geometry,
        COALESCE(start_decdate, isodatetodecimaldate(pad_date(start_date::TEXT, 'start')::TEXT, FALSE)) AS start_decdate,
        COALESCE(end_decdate, isodatetodecimaldate(pad_date(end_date::TEXT, 'end')::TEXT, FALSE)) AS end_decdate,
        me_indefinite,
        me_maritime,
        me_disputed,
        me_disputed_by
      FROM osm_admin_relation_members
      WHERE type <> 'administrative'
        AND ST_GeometryType(geometry) = 'ST_LineString'
    ),
    ordered AS (
      SELECT
        *,
        LAG(end_decdate) OVER (
          PARTITION BY type, admin_level, member
          ORDER BY start_decdate NULLS FIRST
        ) AS prev_end
      FROM members
    ),
    flagged AS (
      SELECT
        *,
        CASE
          WHEN prev_end IS NULL THEN 0
          WHEN start_decdate IS NULL THEN 0
          -- 0.003 covers a one day gap in decimal years, leap year or not
          WHEN (start_decdate - prev_end) < 0.003 THEN 0
          ELSE 1
        END AS gap_flag
      FROM ordered
    ),
    grouped AS (
      SELECT
        *,
        SUM(gap_flag) OVER (
          PARTITION BY type, admin_level, member
          ORDER BY start_decdate NULLS FIRST
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS group_id
      FROM flagged
    ),
    merged AS (
      SELECT
        type,
        admin_level,
        member,
        group_id,
        (ARRAY_AGG(geometry ORDER BY start_decdate NULLS FIRST))[1] AS geometry,
        CASE WHEN BOOL_OR(start_decdate IS NULL) THEN NULL ELSE MIN(start_decdate) END AS start_decdate,
        CASE WHEN BOOL_OR(end_decdate IS NULL) THEN NULL ELSE MAX(end_decdate) END AS end_decdate,
        MAX(me_indefinite) AS indefinite,
        MAX(me_maritime) AS maritime,
        MAX(me_disputed) AS disputed,
        MAX(me_disputed_by) AS disputed_by
      FROM grouped
      GROUP BY type, admin_level, member, group_id
    ),
    relation_lines AS (
      SELECT
        type,
        admin_level,
        member AS osm_id,
        geometry,
        group_id,
        start_decdate,
        end_decdate,
        convert_decimal_to_iso_date(start_decdate::NUMERIC)::VARCHAR AS start_date,
        convert_decimal_to_iso_date(end_decdate::NUMERIC)::VARCHAR AS end_date,
        indefinite,
        maritime,
        disputed,
        disputed_by
      FROM merged
    ),
    way_lines AS (
      SELECT
        l.type,
        l.admin_level,
        l.osm_id,
        l.geometry,
        0::BIGINT AS group_id,
        COALESCE(l.start_decdate, isodatetodecimaldate(pad_date(l.start_date::TEXT, 'start')::TEXT, FALSE)) AS start_decdate,
        COALESCE(l.end_decdate, isodatetodecimaldate(pad_date(l.end_date::TEXT, 'end')::TEXT, FALSE)) AS end_decdate,
        l.start_date,
        l.end_date,
        l.indefinite,
        l.maritime,
        l.disputed,
        l.disputed_by
      FROM osm_admin_lines l
      WHERE l.type <> 'administrative'
        AND l.geometry IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM osm_admin_relation_members m
          WHERE m.member = l.osm_id
            AND m.type = l.type
            AND m.type <> 'administrative'
        )
    ),
    all_lines AS (
      SELECT * FROM relation_lines
      UNION ALL
      SELECT * FROM way_lines
    )
    SELECT
      ROW_NUMBER() OVER (ORDER BY type, admin_level, osm_id, group_id) AS id,
      type,
      admin_level,
      osm_id,
      ST_SimplifyPreserveTopology(geometry, 1) AS geometry,
      group_id,
      start_decdate,
      end_decdate,
      NULLIF(start_date, '') AS start_date,
      NULLIF(end_date, '') AS end_date,
      NULLIF(indefinite, '') AS indefinite,
      NULLIF(maritime, '') AS maritime,
      NULLIF(disputed, '') AS disputed,
      NULLIF(disputed_by, '') AS disputed_by
    FROM all_lines
    $sql$
);

-- ============================================================================
-- STEP 2: Lower zooms
-- Lines with admin_level follow the zoom ranges of the admin lines.
-- Lines without admin_level show from zoom 8, except timezone, which shows at every zoom.
-- ============================================================================
SELECT derive_line_mview(
    source           => 'mv_non_admin_boundaries_lines_z16_20',
    target           => 'mv_non_admin_boundaries_lines_z13_15',
    simplify_tol     => 5,
    where_filter     => 'admin_level IS NULL OR admin_level IN (1,2,3,4,5,6,7,8,9,10)'
);
SELECT derive_line_mview(
    source           => 'mv_non_admin_boundaries_lines_z13_15',
    target           => 'mv_non_admin_boundaries_lines_z10_12',
    simplify_tol     => 20
);
SELECT derive_line_mview(
    source           => 'mv_non_admin_boundaries_lines_z10_12',
    target           => 'mv_non_admin_boundaries_lines_z8_9',
    simplify_tol     => 100,
    where_filter     => 'admin_level IS NULL OR admin_level IN (1,2,3,4,5,6,7,8,9)'
);
SELECT derive_line_mview(
    source           => 'mv_non_admin_boundaries_lines_z8_9',
    target           => 'mv_non_admin_boundaries_lines_z6_7',
    simplify_tol     => 200,
    where_filter     => 'type = ''timezone'' OR admin_level IN (1,2,3,4,5,6)'
);
SELECT derive_line_mview(
    source           => 'mv_non_admin_boundaries_lines_z6_7',
    target           => 'mv_non_admin_boundaries_lines_z3_5',
    simplify_tol     => 1000,
    where_filter     => 'type = ''timezone'' OR admin_level IN (1,2,3,4)'
);
SELECT derive_line_mview(
    source           => 'mv_non_admin_boundaries_lines_z3_5',
    target           => 'mv_non_admin_boundaries_lines_z0_2',
    simplify_tol     => 5000,
    where_filter     => 'type = ''timezone'' OR admin_level IN (1,2)'
);

-- ============================================================================
-- STEP 3: Views that the land_ohm_lines layer reads
-- Plain views, so they need no refresh.
-- ============================================================================
DO $$
DECLARE
  zoom TEXT;
  cols TEXT := 'id, type, admin_level, osm_id, geometry, group_id, start_decdate, end_decdate, start_date, end_date, indefinite, maritime, disputed, disputed_by';
BEGIN
  FOREACH zoom IN ARRAY ARRAY['z16_20', 'z13_15', 'z10_12', 'z8_9', 'z6_7', 'z3_5', 'z0_2']
  LOOP
    EXECUTE format(
      'CREATE OR REPLACE VIEW land_ohm_lines_%1$s AS
       SELECT %2$s FROM mv_admin_boundaries_lines_%1$s
       UNION ALL
       SELECT %2$s FROM mv_non_admin_boundaries_lines_%1$s',
      zoom, cols
    );
  END LOOP;
END $$;
