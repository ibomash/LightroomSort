local Core = require 'Core'
local Operations = {}

local function exactMatch(objects, name, kind)
    local found
    for _, object in ipairs(objects) do
        if object:getName() == name then
            if found then error('Multiple ' .. kind .. ' named "' .. name .. '". Resolve this before organizing.', 0) end
            found = object
        end
    end
    return found
end

-- Read every destination before creating anything. Never query a newly created
-- collection/set: SDK getters generally cannot access it until the gate commits.
function Operations.preflight(catalog, plan)
    local years, destinations = {}, {}
    local topSets, topCollections = catalog:getChildCollectionSets(), catalog:getChildCollections()
    for _, item in ipairs(plan) do
        if not years[item.year] then
            local set = exactMatch(topSets, item.year, 'top-level collection sets')
            if exactMatch(topCollections, item.year, 'top-level collections') then
                error('A top-level collection conflicts with year set "' .. item.year .. '".', 0)
            end
            years[item.year] = { set = set }
        end
        local set = years[item.year].set
        local collection
        if set then
            collection = exactMatch(set:getChildCollections(), item.name, 'collections')
            if exactMatch(set:getChildCollectionSets(), item.name, 'collection sets') then
                error('A collection set conflicts with "' .. item.name .. '".', 0)
            end
            if collection and collection:isSmartCollection() then
                error('The destination "' .. item.name .. '" is a smart collection.', 0)
            end
        end
        local members = {}
        if collection then
            for _, photo in ipairs(collection:getPhotos()) do members[photo.localIdentifier] = true end
        end
        local additions = {}
        for _, photo in ipairs(item.photos) do
            if Core.photoDate(photo) ~= item.date then
                error('A capture date changed while the dialog was open. Run Daily Collections again.', 0)
            end
            if not members[photo.localIdentifier] then additions[#additions + 1] = photo end
        end
        destinations[#destinations + 1] = { item = item, collection = collection, additions = additions }
    end
    return years, destinations
end

function Operations.organize(catalog, plan)
    local result = { organized = 0, added = 0, cleared = 0, created = 0, reused = 0, dates = {} }
    local committed = false
    local status = catalog:withWriteAccessDo('Organize Into Daily Collections', function()
        -- Repeat the preflight under the gate so another writer cannot invalidate it.
        local years, destinations = Operations.preflight(catalog, plan)
        for _, destination in ipairs(destinations) do
            local item = destination.item
            local year = years[item.year]
            if not year.set then
                year.set = catalog:createCollectionSet(item.year, nil, false)
                if not year.set then error('Could not create year set "' .. item.year .. '".', 0) end
            end
            local collection = destination.collection
            if not collection then
                collection = catalog:createCollection(item.name, year.set, false)
                if not collection then error('Could not create collection "' .. item.name .. '".', 0) end
                result.created = result.created + 1
            else
                result.reused = result.reused + 1
            end
            if #destination.additions > 0 then collection:addPhotos(destination.additions) end
            -- An exception here escapes the callback and rolls back ALL changes,
            -- including memberships and any labels cleared for earlier dates.
            for _, photo in ipairs(item.photos) do
                if photo:getRawMetadata('colorNameForLabel') == 'purple' then
                    photo:setRawMetadata('label', '')
                    result.cleared = result.cleared + 1
                end
            end
            result.organized = result.organized + #item.photos
            result.added = result.added + #destination.additions
            result.dates[#result.dates + 1] = { date = item.date, event = item.event, count = #item.photos }
        end
        committed = true
    end, { timeout = 10, asynchronous = false })
    if not committed or status ~= 'executed' then
        error('Could not obtain catalog write access. No changes were made. Try again when Lightroom is idle.', 0)
    end
    return result
end

return Operations
