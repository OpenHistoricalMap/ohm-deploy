-- ============================================================================
--This is fuction to convert decimal date to iso date, in that it handles BCE dates properly, and it also returns NULL if any conversion error happens.
--It is used in images/tiler-imposm/queries/mviews_admin_boundaries_merged.sql
--This script differs from https://github.com/OpenHistoricalMap/DateFunctions-plpgsql/blob/master/datefunctions.sql
-- ============================================================================
CREATE OR REPLACE FUNCTION convert_decimal_to_iso_date(decimal_date NUMERIC)
RETURNS VARCHAR AS $$
DECLARE
    year_part INT;
    decimal_part NUMERIC;
    days_in_year INT;
    day_of_year INT;
    final_date DATE;
    formatted_year VARCHAR;
BEGIN
    IF decimal_date IS NULL THEN
        RETURN NULL;
    END IF;

    year_part := FLOOR(decimal_date);
    decimal_part := decimal_date - year_part;

    -- Determine number of days in the year (leap year check)
    days_in_year := CASE 
        WHEN (year_part % 4 = 0 AND year_part % 100 <> 0) OR (year_part % 400 = 0) 
        THEN 366  -- Leap year
        ELSE 365  -- Regular year
    END;

    -- Convert decimal fraction to day of the year
    day_of_year := CEIL(decimal_part * days_in_year);

    -- Format the year properly for BCE cases
    IF year_part < 1 THEN
        formatted_year := LPAD(ABS(year_part - 1)::TEXT, 4, '0');  -- Convert BCE format
        formatted_year := '-' || formatted_year;  -- Add negative sign for BCE
    ELSE
        formatted_year := LPAD(year_part::TEXT, 4, '0');
    END IF;

    -- Try converting year + day-of-year into full ISO date
    BEGIN
        final_date := TO_DATE(formatted_year || '-' || day_of_year, 'YYYY-DDD');
    EXCEPTION
        WHEN others THEN
            RETURN NULL;  -- If any conversion error happens, return NULL
    END;

    RETURN TO_CHAR(final_date, 'YYYY-MM-DD');
END;
$$
LANGUAGE plpgsql;

-- ============================================================================
--  This function converts a date in ISO format to a decimal date. usually user in triggers
-- ============================================================================
CREATE OR REPLACE FUNCTION convert_dates_to_decimal ()
RETURNS TRIGGER AS
$$
BEGIN
    NEW.start_decdate := isodatetodecimaldate(pad_date(NEW.start_date::TEXT, 'start')::TEXT, FALSE);
    NEW.end_decdate := isodatetodecimaldate(pad_date(NEW.end_date::TEXT, 'end')::TEXT, FALSE);
    RETURN NEW;
END;
$$
LANGUAGE plpgsql;

-- ============================================================================
--  This function is used to log text for tracking purposes.
-- ============================================================================
CREATE OR REPLACE FUNCTION log_notice(msg TEXT)
RETURNS void AS $$
BEGIN
  RAISE NOTICE '%', msg;
END;
$$ LANGUAGE plpgsql;

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
        format(
            'tags -> %L AS %I',
            key_name,
            'name_' || regexp_replace(lower(substring(key_name from 6)), '[^a-z0-9]', '_', 'g')
        ),
        ', '
    )
    INTO result
    FROM languages;

    RETURN COALESCE(result, '');
END;
$$ LANGUAGE plpgsql;
