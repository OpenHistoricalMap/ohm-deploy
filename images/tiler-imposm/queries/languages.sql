--============================================================================
-- Script: Language Extraction and Change Detection from Vtiles Tables
-- Description:
-- This script extracts all language keys (tags starting with name:xx) from a
-- fixed list of OSM-related tables that contain `tags` in hstore format.
-- It stores the detected languages in the `languages` table and calculates
-- a hash of the current set to detect changes over time.

-- Features:
--        - Scans OSM tables for valid language tags using a strict regex.
--        - Stores tag aliases and counts in the `languages` table.
--        - Computes a hash of the current language list.
--        - Tracks whether the hash has changed since the previous run.
-- ============================================================================

-- Table to store valid language tags detected in OSM data
CREATE TABLE IF NOT EXISTS languages (
    alias TEXT PRIMARY KEY,
    key_name TEXT NOT NULL,
    count INTEGER,
    date_added TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table to store hashes of the language list for change detection
CREATE TABLE IF NOT EXISTS languages_hash (
    id SERIAL PRIMARY KEY,
    hash TEXT NOT NULL,
    has_changed BOOLEAN NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Function to update the `languages` table by scanning specified tables
CREATE OR REPLACE FUNCTION update_languages_from_tables(min_count INTEGER DEFAULT 5)
RETURNS void AS $$
DECLARE
    tbl TEXT;
    rec RECORD;
    lang_key TEXT;
    lang_alias TEXT;
    lang_count INT;
    language_regex TEXT := '^name:[a-z]{2,3}(-[A-Z][a-z]{3})?((-[a-z]{2,}|x-[a-z]{2,})(-[a-z]{2,})?)?(-([A-Z]{2}|\\d{3}))?$';
BEGIN
    -- Clear existing languages to fully regenerate
    DELETE FROM languages;

    -- List of relevant OSM tables to evaluate
    FOR tbl IN 
        SELECT unnest(ARRAY[
            'osm_admin_areas',
            'osm_admin_lines',
            'osm_amenity_areas',
            'osm_amenity_points',
            'osm_buildings_points',
            'osm_buildings',
            'osm_landuse_areas',
            'osm_landuse_lines',
            'osm_landuse_points',
            'osm_other_areas',
            'osm_other_lines',
            'osm_other_points',
            'osm_place_areas',
            'osm_place_points',
            'osm_relation_members_boundaries',
            'osm_relations',
            'osm_transport_areas',
            'osm_transport_lines',
            'osm_transport_multilines',
            'osm_transport_points',
            'osm_water_areas',
            'osm_water_lines'
        ])
    LOOP
        FOR rec IN EXECUTE format(
            $sql$
            SELECT
                key AS lang_key,
                count(*) AS lang_count
            FROM (
                SELECT skeys(tags) AS key
                FROM %I
                WHERE tags IS NOT NULL
            ) sub
            WHERE key ~ %L
            GROUP BY key
            HAVING count(*) >= %s
            $sql$,
            tbl,
            language_regex,
            min_count
        )
        LOOP
            lang_key := rec.lang_key;
            lang_count := rec.lang_count;
            lang_alias := replace(replace(lower(lang_key), ':', '_'), '-', '_');

            -- Insert or update the language in the `languages` table
            INSERT INTO languages(alias, key_name, count)
            VALUES (lang_alias, lang_key, lang_count)
            ON CONFLICT (alias) DO UPDATE
            SET count = EXCLUDED.count,
                date_added = CURRENT_TIMESTAMP;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'Languages updated from OSM tables with min_count=%', min_count;
END;
$$ LANGUAGE plpgsql;

-- Function to insert a new hash and detect if it differs from the previous one
CREATE OR REPLACE FUNCTION insert_languages_hash_if_changed()
RETURNS BOOLEAN AS $$
DECLARE
    current_hash TEXT;
    last_hash TEXT;
    is_changed BOOLEAN;
BEGIN
    SELECT md5(string_agg(alias, ',' ORDER BY alias))
    INTO current_hash
    FROM languages;

    -- Get most recent hash
    SELECT hash INTO last_hash
    FROM languages_hash
    ORDER BY created_at DESC
    LIMIT 1;

    -- Check if it changed
    is_changed := last_hash IS NULL OR current_hash IS DISTINCT FROM last_hash;

    -- Insert the new hash record
    INSERT INTO languages_hash (hash, has_changed)
    VALUES (current_hash, is_changed);

    RAISE NOTICE 'Inserted hash: %, has_changed: %', current_hash, is_changed;
    RETURN is_changed;
END;
$$ LANGUAGE plpgsql;

-- Example execution
SELECT update_languages_from_tables(10);
SELECT insert_languages_hash_if_changed();