-- ============================================================================
-- Function: search_languages()
-- 
-- Description:
--   Scans all relevant tables to extract language tags of the form `name:*`,
--   following a strict regex pattern that matches BCP 47 language codes.
--   For each matching language key, it calculates:
--     - A normalized alias (lowercase, with ':' and '-' replaced by '_')
--     - The original key as it appears in the tags (e.g., 'name:es', 'name:ar-Latn')
--     - The total number of objects containing that key
--     - A bounding box (geometry) that encompasses all matching features
-- 
-- Returns:
--   - alias TEXT         -- normalized form, safe for database use (e.g., 'name_es')
--   - language_key TEXT  -- original OHM tag key (e.g., 'name:es')
--   - total_count BIGINT -- number of features with this key
--   - bbox GEOMETRY      -- bounding box for all matching geometries

-- ============================================================================

CREATE OR REPLACE FUNCTION search_languages()
RETURNS TABLE(
    alias TEXT,              -- normalized and lowercase alias
    language_key TEXT,       -- original tag key like 'name:es'
    total_count BIGINT,      -- number of objects with this key
    bbox GEOMETRY            -- bounding box of all geometries with this key
) AS $$
BEGIN
    RETURN QUERY
    WITH all_ohm_data AS (
        SELECT tags, geometry FROM osm_admin_areas WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_admin_lines WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_amenity_areas WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_amenity_points WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_buildings_points WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_buildings WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_landuse_areas WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_landuse_lines WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_landuse_points WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_other_areas WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_other_lines WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_other_points WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_place_areas WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_place_points WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_transport_areas WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_transport_lines WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_transport_multilines WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_transport_points WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_water_areas WHERE tags IS NOT NULL AND geometry IS NOT NULL
        UNION ALL SELECT tags, geometry FROM osm_water_lines WHERE tags IS NOT NULL AND geometry IS NOT NULL
    )
    SELECT
        lower(regexp_replace(keys.key, '[:\-]', '_', 'g')) AS alias,
        keys.key AS language_key,
        COUNT(*) AS total_count,
        CAST(ST_Extent(all_ohm_data.geometry) AS GEOMETRY) AS bbox
    FROM
        all_ohm_data,
        LATERAL each(all_ohm_data.tags) AS keys(key, value)
    WHERE
        keys.key ~ '^name:[a-z]{2,3}(-[A-Z][a-z]{3})?((-[a-z]{2,}|x-[a-z]{2,})(-[a-z]{2,})?)?(-([A-Z]{2}|\\d{3}))?$'
    GROUP BY
        keys.key
    ORDER BY
        total_count DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Function: populate_languages(min_number_languages INTEGER, force BOOLEAN)
-- 
-- Description:
--   This function populates the 'languages' table with entries from the 
--   'search_languages()' function, which returns language usage across various
--   vector tile source tables. It is designed to track which language tags 
--   (e.g., name:es, name:fr) are actively used in the dataset.
--
--   The function applies the following logic:
--
--     1. If the 'languages' table does not exist, it is created.
--     2. If 'force' is TRUE, all existing rows in 'languages' are deleted.
--        Otherwise, all rows are marked as is_new = FALSE.
--     3. New or updated languages are inserted from 'search_languages()', 
--        filtering out any that appear fewer than 'min_number_languages' times.
--     4. If a language already exists, its count, bbox, and date_added fields 
--        are updated — but its is_new flag is left unchanged (i.e., stays FALSE).
--     5. New entries are inserted with is_new = TRUE by default.
--
--   This approach ensures that only truly new languages are flagged as 'is_new',
--   which is useful for detecting newly added languages and triggering processes
--   like materialized view updates or tile regeneration.
--
-- Parameters:
--   min_number_languages - Minimum number of tagged objects required for a 
--                          language to be considered valid.
--   force                - If TRUE, wipes the table and treats all inserted 
--                          languages as new.
--
-- Example Usage:
--   SELECT populate_languages(5, FALSE);  -- normal run, only mark new
--   SELECT populate_languages(5, TRUE);   -- full rebuild, all treated as new
-- ============================================================================

CREATE OR REPLACE FUNCTION populate_languages(min_number_languages INTEGER, force BOOLEAN DEFAULT FALSE)
RETURNS VOID AS $$
BEGIN
    -- Step 1: Create the table if it doesn't exist
    EXECUTE $create$
        CREATE TABLE IF NOT EXISTS languages (
            alias TEXT PRIMARY KEY,
            key_name TEXT NOT NULL,
            count INTEGER,
            date_added TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
            is_new BOOLEAN DEFAULT TRUE,
            bbox GEOMETRY
        );
    $create$;

    -- Step 2: Delete or reset is_new flag
    IF force THEN
        DELETE FROM languages;
    ELSE
        UPDATE languages SET is_new = FALSE;
    END IF;

    -- Step 3: Insert new or update existing languages
    EXECUTE format($sql$
        INSERT INTO languages (alias, key_name, count, bbox)
        SELECT
            alias,
            MIN(language_key) AS key_name,
            SUM(total_count)::INTEGER AS count,
            CASE
                WHEN GeometryType(ST_Envelope(ST_Collect(bbox))) = 'POINT' THEN
                    ST_Envelope(ST_Buffer(ST_Envelope(ST_Collect(bbox))::geography, 10)::geometry)
                ELSE
                    ST_Envelope(ST_Collect(bbox))
            END AS bbox
        FROM
            search_languages()
        GROUP BY
            alias
        HAVING
            SUM(total_count) >= %s
        ON CONFLICT (alias) DO UPDATE SET
            count = EXCLUDED.count,
            bbox = EXCLUDED.bbox,
            date_added = CURRENT_TIMESTAMP;
    $sql$, min_number_languages);
END;
$$ LANGUAGE plpgsql;
-- ============================================================================
-- Populate languages with a default of 5 features, forcing an update:
-- ============================================================================

select populate_languages(5, TRUE);
