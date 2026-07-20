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
-- This must hook process_tags, not osm2pgsql.process_relation: osm2pgsql
-- captures the process_* callbacks on the Lua stack before this file can
-- override them, so a reassignment of osm2pgsql.process_relation is never
-- called. process_tags is looked up dynamically on the flex module table,
-- so wrapping it here does take effect.
local original_process_tags = flex.process_tags

function flex.process_tags(o)
    if o.object.type == 'relation' then
        local tags = o.object.tags
        if tags.type == 'street' and tags.highway == nil then
            tags.highway = 'road'
        elseif tags.type == 'route' and tags.route == 'road' and tags.highway == nil then
            tags.highway = 'road'
        elseif tags.type == 'chronology' and tags.historic == nil then
            tags.historic = 'chronology'
        end
    end
    original_process_tags(o)
end

return flex
