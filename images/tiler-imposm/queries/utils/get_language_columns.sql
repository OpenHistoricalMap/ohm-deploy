-- ============================================================================
-- Function: get_language_columns(prefix TEXT)
-- Description:
--   Returns a comma-separated list of SQL expressions like:
--     prefix.tags -> 'name:es' AS "name_es"
--   Based on aliases found in the `languages` table.
--
-- Example:
--   get_language_columns('r.') → "r.tags->'name:es' AS name_es, ..."
-- ============================================================================

CREATE OR REPLACE FUNCTION get_language_columns(prefix TEXT)
RETURNS TEXT AS $$
DECLARE
    result TEXT;
BEGIN
    SELECT string_agg(
        format('%s.tags -> %L AS %I', prefix, 'name:' || alias, 'name_' || alias),
        ', '
    )
    INTO result
    FROM languages;

    RETURN COALESCE(result, '');
END;
$$ LANGUAGE plpgsql;
