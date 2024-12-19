DO $$
DECLARE
    trigger_name TEXT;
    table_name TEXT;
BEGIN
    -- Loop through all triggers for tables matching the pattern
    FOR trigger_name, table_name IN
        SELECT tgname, relname
        FROM pg_trigger
        JOIN pg_class ON pg_trigger.tgrelid = pg_class.oid
        JOIN pg_namespace ON pg_class.relnamespace = pg_namespace.oid
        WHERE nspname = 'public' -- Adjust schema if needed
          AND relname LIKE 'osm_admin_boundaries_centroid_%'
          AND NOT tgisinternal -- Exclude internal triggers
    LOOP
        -- Dynamically drop the trigger if it exists
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I;', trigger_name, table_name);
        RAISE NOTICE 'Dropped trigger % on table %', trigger_name, table_name;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create a function that updates the osm_admin_boundaries_centroid_* if relations have labels or not
CREATE OR REPLACE FUNCTION update_admin_boundaries_centroids()
RETURNS void AS $$
DECLARE
    table_name text;
    updated_rows integer;
BEGIN
    -- Log the start of the update process
    RAISE NOTICE 'Starting the update of admin boundaries centroids at %', clock_timestamp();

    -- Loop through all table names that match the pattern
    FOR table_name IN
        SELECT t.table_name
        FROM information_schema.tables AS t
        WHERE t.table_name LIKE 'osm_admin_boundaries_centroid%'
    LOOP
        -- Dynamically execute the update query for each table
        BEGIN
            EXECUTE format('
                WITH updated AS (
                    UPDATE %I
                    SET has_label = 1
                    WHERE osm_id IN (
                        SELECT osm_id
                        FROM osm_relation_members
                        WHERE role = ''label''
                    )
                    RETURNING *
                )
                SELECT COUNT(*) FROM updated;', table_name)
            INTO updated_rows;

            -- Log the number of updated rows
            RAISE NOTICE 'Table % updated. Rows affected: %', table_name, updated_rows;

        EXCEPTION WHEN OTHERS THEN
            -- Log any errors encountered
            RAISE NOTICE 'Error updating table %: %', table_name, SQLERRM;
        END;
    END LOOP;

    -- Log completion
    RAISE NOTICE 'Update process completed for all matching tables at %.', clock_timestamp();
END;
$$ LANGUAGE plpgsql;

-- Execute the update function when the import is done
SELECT update_admin_boundaries_centroids();

CREATE OR REPLACE FUNCTION create_update_has_label_triggers()
RETURNS void AS $$
DECLARE
    table_name text;
    pattern text := 'osm_admin_boundaries_centroid_%'; -- Fixed pattern
BEGIN
    -- Log the start of the trigger creation process
    RAISE NOTICE 'Starting the creation of triggers for tables matching pattern: %', pattern;

    -- Loop through all tables matching the fixed pattern
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
                 RAISE NOTICE ''Trigger activated for table %% with osm_id: %%'', TG_TABLE_NAME, NEW.osm_id;

                 IF EXISTS (
                     SELECT 1
                     FROM osm_relation_members
                     WHERE osm_id = NEW.osm_id AND role = ''label''
                 ) THEN
                     NEW.has_label := 1;
                     RAISE NOTICE ''Set has_label to 1 for osm_id: %%'', NEW.osm_id;
                 ELSE
                     NEW.has_label := 0;
                     RAISE NOTICE ''Set has_label to 0 for osm_id: %%'', NEW.osm_id;
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

        -- Log the trigger creation for the current table
        RAISE NOTICE 'Trigger and function created for table: %', table_name;
    END LOOP;

    -- Log completion of the trigger creation process
    RAISE NOTICE 'All triggers created for tables matching pattern: %.', pattern;
END;
$$ LANGUAGE plpgsql;

-- Execute the function to create triggers for tables matching the pattern
SELECT create_update_has_label_triggers();
