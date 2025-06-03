-- ============================================================================
-- Function: refresh_all_osm_amenity_areas(force_create BOOLEAN)
-- Description:
--   Calls the generic materialized view creation function for amenity areas.
--   This function generates the view used for zoom levels 14–20.
-- ============================================================================

DROP FUNCTION IF EXISTS refresh_all_osm_amenity_areas(BOOLEAN);

CREATE OR REPLACE FUNCTION refresh_all_osm_amenity_areas(force_create BOOLEAN DEFAULT FALSE)
RETURNS void AS $$
BEGIN
  PERFORM create_or_refresh_generic_mview(
    'osm_amenity_areas',
    'mv_amenity_areas_z14_20',
    force_create,
    ARRAY['osm_id', 'type']
  );
  RAISE NOTICE '✅ Amenity areas materialized view created/refreshed.';
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- Execute force creation of all amenity areas materialized views
-- ============================================================================
SELECT refresh_all_osm_amenity_areas(TRUE); 
