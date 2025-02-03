
-- Create a function to validate dates

CREATE OR REPLACE FUNCTION is_date_valid(date_text text) RETURNS boolean AS $$
DECLARE
    tmp_date date;
BEGIN
    -- Try the format YYYY-MM-DD
    BEGIN
        tmp_date := to_date(date_text, 'YYYY-MM-DD');
        RETURN TRUE;
    EXCEPTION WHEN others THEN
    END;

    -- Try the format YYYY-MM
    BEGIN
        tmp_date := to_date(date_text || '-01', 'YYYY-MM-DD');
        RETURN TRUE;
    EXCEPTION WHEN others THEN
    END;

    -- Try the format YYYY
    BEGIN
        tmp_date := to_date(date_text || '-01-01', 'YYYY-MM-DD');
        RETURN TRUE;
    EXCEPTION WHEN others THEN
    END;
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;