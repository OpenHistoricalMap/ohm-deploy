-- ============================================================================
-- Function: refresh_mview
-- Description:
--   Checks if the materialized view exists and whether the languages hash
--   has changed. If the view exists and the languages hash hasn't changed,
--   it refreshes the view and returns FALSE (no need to recreate).
--   Otherwise, returns TRUE (should recreate the view).
--
-- Parameters:
--   view_name TEXT - The name of the materialized view to check.
--
-- Returns:
--   BOOLEAN - TRUE if the view should be recreated, FALSE if only refreshed.
-- ============================================================================
CREATE OR REPLACE FUNCTION refresh_mview(view_name TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    view_exists BOOLEAN;
    lang_changed BOOLEAN;
    refresh_sql TEXT;
BEGIN
    -- Check if the materialized view exists
    SELECT EXISTS (
        SELECT 1 FROM pg_matviews WHERE matviewname = view_name
    ) INTO view_exists;

    -- Check if the language hash has changed
    SELECT insert_languages_hash_if_changed() INTO lang_changed;

    IF view_exists AND NOT lang_changed THEN
        -- Refresh only
        refresh_sql := format('REFRESH MATERIALIZED VIEW CONCURRENTLY %I;', view_name);
        RAISE NOTICE 'No language changes. Refreshing view: %', view_name;
        EXECUTE refresh_sql;
        RETURN FALSE;
    END IF;

    -- Should recreate
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
