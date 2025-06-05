-- ============================================================================
-- Function: get_language_columns()
-- Description:
--   Returns a comma-separated list of SQL expressions like:
--     tags -> 'name:es' AS "es"
--   Based on aliases found in the `languages` table.
--
-- Notes:
--   - Designed for direct use when `tags` is accessed without a table alias.
--   - Useful for generating multilingual columns dynamically in SQL queries.
--
-- Example:
--   get_language_columns() → "tags->'name:es' AS es, tags->'name:fr' AS fr, ..."
-- ============================================================================
CREATE OR REPLACE FUNCTION get_language_columns()
RETURNS TEXT AS $$
DECLARE
    result TEXT;
BEGIN
    SELECT string_agg(
        format('tags -> %L AS %I', 'name:' || alias, alias),
        ', '
    )
    INTO result
    FROM languages;

    RETURN COALESCE(result, '');
END;
$$ LANGUAGE plpgsql;
