-- Create a function that updates the osm_admin_boundaries_centroid_* if relations have labels or not
CREATE OR REPLACE FUNCTION update_admin_boundaries_centroids()
RETURNS void AS $$
DECLARE
    table_name text;
BEGIN
    -- Loop through all table names that match the pattern
    FOR table_name IN
        SELECT t.table_name
        FROM information_schema.tables AS t
        WHERE t.table_name LIKE 'osm_admin_boundaries_centroid%'
    LOOP
        -- Dynamically execute the update query for each table
        BEGIN
            EXECUTE format('
                UPDATE %I
                SET has_label = 1
                WHERE osm_id IN (
                    SELECT osm_id
                    FROM osm_relation_members
                    WHERE role = ''label''
                );', table_name);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE ''Error updating table %: %'', table_name, SQLERRM;
        END;
    END LOOP;

    -- Log completion
    RAISE NOTICE ''Update completed for all matching tables.'';
END;
$$ LANGUAGE plpgsql;

-- Create a function that updates the osm_admin_boundaries_centroid_* if relations have labels or not
CREATE OR REPLACE FUNCTION create_update_has_label_triggers(pattern text)
RETURNS void AS $$
DECLARE
    table_name text;
BEGIN
    -- Loop through all tables matching the provided pattern
    FOR table_name IN
        SELECT t.table_name
        FROM information_schema.tables AS t
        WHERE t.table_name LIKE pattern
    LOOP
        -- Create a dynamic function for each table
        EXECUTE format(
            'CREATE OR REPLACE FUNCTION %I_update_has_label_row()
             RETURNS TRIGGER AS $trigger_body$
             BEGIN
                 IF EXISTS (
                     SELECT 1
                     FROM osm_relation_members
                     WHERE osm_id = NEW.osm_id AND role = ''label''
                 ) THEN
                     NEW.has_label := 1;
                 ELSE
                     NEW.has_label := 0;
                 END IF;
                 RETURN NEW;
             END;
             $trigger_body$ LANGUAGE plpgsql;',
            table_name
        );

        -- Attach a trigger to each table
        EXECUTE format(
            'CREATE TRIGGER %I_trigger_update_has_label
             BEFORE INSERT OR UPDATE ON %I
             FOR EACH ROW
             EXECUTE FUNCTION %I_update_has_label_row();',
            table_name, -- Trigger name
            table_name, -- Table name
            table_name  -- Function name
        );
    END LOOP;

    RAISE NOTICE 'Triggers and functions created for tables matching %.', pattern;
END;
$$ LANGUAGE plpgsql;


-- Execute the update function when the import is done
SELECT update_admin_boundaries_centroids();

-- Execute the function to create triggers for tables matching the pattern
SELECT create_update_has_label_triggers('osm_admin_boundaries_centroid%');
