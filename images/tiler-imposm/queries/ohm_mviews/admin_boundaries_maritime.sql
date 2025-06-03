-- ============================================================================
-- Function: refresh_all_admin_maritime_lines(force_create BOOLEAN)
-- Description:
--   Calls a generic materialized view creation function for maritime lines
--   grouped by different zoom-level tables.
-- ============================================================================

DROP FUNCTION IF EXISTS refresh_all_admin_maritime_lines(BOOLEAN);

CREATE OR REPLACE FUNCTION refresh_all_admin_maritime_lines(force_create BOOLEAN DEFAULT FALSE)
RETURNS void AS $$
BEGIN
  -- Z0–5: Generalized geometry for low zoom levels
  PERFORM create_or_refresh_generic_mview(
    'osm_admin_lines_z0_5',                     -- Source table
    'mv_admin_maritime_lines_z0_5',             -- Target materialized view
    force_create,                               -- Force recreation?
    ARRAY['osm_id', 'type']                     -- Required unique columns
  );

  PERFORM create_or_refresh_generic_mview(
    'osm_admin_lines_z6_9',
    'mv_admin_maritime_lines_z6_9',
    force_create,
    ARRAY['osm_id', 'type']
  );

  PERFORM create_or_refresh_generic_mview(
    'osm_admin_lines_z10_15',
    'mv_admin_maritime_lines_z10_15',
    force_create,
    ARRAY['osm_id', 'type']
  );

  RAISE NOTICE '✅ All maritime admin line materialized views created/refreshed.';
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Execute force creation of all admin boundaries centroids materialized views
-- ============================================================================
SELECT refresh_all_admin_maritime_lines(TRUE); 
