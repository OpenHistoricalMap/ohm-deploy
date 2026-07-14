-- OHM import style, extends the standard 'extratags' style.
-- Indexes street and collection relations by name:
-- https://github.com/OpenHistoricalMap/issues/issues/1308
-- https://github.com/OpenHistoricalMap/issues/issues/452

local flex = require('import-extratags')

flex.RELATION_TYPES['street'] = flex.relation_as_multiline
flex.RELATION_TYPES['collection'] = flex.relation_as_multiline
flex.RELATION_TYPES['route'] = flex.relation_as_multiline

-- Street and railway route relations carry only identity tags (type, name,
-- dates), so give them a generic main tag to get the same ranks as named
-- highway/railway ways.
local original_process_relation = osm2pgsql.process_relation

function osm2pgsql.process_relation(object)
    local tags = object.tags
    if tags.type == 'street' and tags.highway == nil then
        tags.highway = 'road'
    elseif tags.type == 'route' and tags.route == 'railway' and tags.railway == nil then
        tags.railway = 'rail'
    end
    original_process_relation(object)
end

return flex
