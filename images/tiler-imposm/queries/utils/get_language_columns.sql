-- ============================================================================
-- Function: get_language_columns()
-- Description:
--   Returns a comma-separated string of SQL expressions to extract language
--   tag values from the `tags` hstore using the `languages` table.
--
-- Output:
--   TEXT - e.g., "tags -> 'name:es' AS name_es, tags -> 'name:fr' AS name_fr"
-- ============================================================================
DROP FUNCTION IF EXISTS get_language_columns;
CREATE OR REPLACE FUNCTION get_language_columns()
RETURNS TEXT AS $$
DECLARE
    lang_columns TEXT;
BEGIN
    SELECT string_agg(
        format('tags -> %L AS %I', key_name, alias),
        ', '
    ) INTO lang_columns
    FROM languages;

    RETURN lang_columns;
END;
$$ LANGUAGE plpgsql;
