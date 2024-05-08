-- Create a function that updates the osm_admin_areas if the polygon has a label in the relations
CREATE OR REPLACE FUNCTION update_admin_areas()
RETURNS void AS $$
BEGIN
    UPDATE osm_admin_areas
    SET has_label = 1
    WHERE osm_id IN (
        SELECT osm_id
        FROM osm_relation_members
        WHERE role = 'label'
    );
END;
$$ LANGUAGE plpgsql;

-- Execute the function
SELECT update_admin_areas();


-- Create a function and trigger that will update every time a new admin area is inserted or updated in  osm_admin_areas table

CREATE OR REPLACE FUNCTION update_has_label_row()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM osm_relation_members
        WHERE osm_id = NEW.osm_id AND role = 'label'
    ) THEN
        NEW.has_label := 1;
    ELSE
        NEW.has_label := 0;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trigger_update_has_label
BEFORE INSERT OR UPDATE ON osm_admin_areas
FOR EACH ROW
EXECUTE FUNCTION update_has_label_row();