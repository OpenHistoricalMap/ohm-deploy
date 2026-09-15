-- OHM import style, extends the standard 'extratags' style.
-- Indexes extra relation types by name:
--   type=street     https://github.com/OpenHistoricalMap/issues/issues/1308
--   type=collection https://github.com/OpenHistoricalMap/issues/issues/452
--   type=chronology https://github.com/OpenHistoricalMap/issues/issues/640
--   type=route, type=site

local flex = require('import-extratags')

-- Members of chronology and site relations are a mix of areas, ways and
-- nodes, so try each geometry kind in turn. A null geometry (for example a
-- relation whose members are only other relations, which osm2pgsql does not
-- resolve) makes flex-base skip the object.
local function relation_as_any(o)
    local geom = o:as_multipolygon()
    if geom:is_null() then
        geom = o:as_multilinestring():line_merge()
    end
    if geom:is_null() then
        geom = o:as_multipoint()
    end
    return geom
end

flex.RELATION_TYPES['street'] = flex.relation_as_multiline
flex.RELATION_TYPES['route'] = flex.relation_as_multiline
flex.RELATION_TYPES['collection'] = relation_as_any
flex.RELATION_TYPES['chronology'] = relation_as_any
flex.RELATION_TYPES['site'] = relation_as_any

-- Street, road route and chronology relations often carry only identity tags
-- (type, name, dates), so give them a main tag or flex-base drops them.
-- The tag has to be there before the place is built: Nominatim copies the
-- object tags into the place at that point, and a place with no main tag is
-- skipped without ever reaching process_tags. So hook process_relation, which
-- runs first, and point osm2pgsql at the wrapper because the module already
-- handed it the original function.
local original_process_relation = flex.process_relation

function flex.process_relation(object)
    local tags = object.tags
    if tags.type == 'street' and tags.highway == nil then
        tags.highway = 'road'
    elseif tags.type == 'route' and tags.route == 'road' and tags.highway == nil then
        tags.highway = 'road'
    elseif tags.type == 'chronology' and tags.historic == nil then
        tags.historic = 'chronology'
    end
    original_process_relation(object)
end

osm2pgsql.process_relation = flex.process_relation

return flex
