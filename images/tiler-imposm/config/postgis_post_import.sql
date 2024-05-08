-- Create a function that updates the osm_admin_areas if the polygon has a label in the relations
CREATE OR REPLACE FUNCTION update_admin_areas()
RETURNS void AS $$
BEGIN
    UPDATE osm_admin_areas
    SET has_label = TRUE
    WHERE osm_id IN (
        SELECT osm_id
        FROM osm_relation_members
        WHERE role = 'label'
    );
END;
$$ LANGUAGE plpgsql;

-- Execute the function
SELECT update_admin_areas();
