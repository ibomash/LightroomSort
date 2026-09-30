package.path = 'DailyCollections.lrplugin/?.lua;' .. package.path
local Core = require 'Core'
local Operations = require 'CatalogOperations'
local passed = 0
local function test(name, fn)
    fn()
    passed = passed + 1
    print('PASS ' .. name)
end
local function equal(a, b) assert(a == b, tostring(a) .. ' ~= ' .. tostring(b)) end
local function fails(fn, text)
    local ok, message = pcall(fn)
    assert(not ok, 'Expected failure')
    assert(tostring(message):find(text, 1, true), tostring(message))
end

-- SDK-shaped doubles model deferred access and rollback, not a real Lightroom
-- runtime. Integration checks are listed separately in docs/TESTING.md.
local function catalogFixture()
    local catalog = { sets = {}, collections = {}, photos = {}, writes = 0, inWrite = false }
    local function readable(object)
        assert(not object.pending or not catalog.inWrite, 'Getter called on uncommitted object')
    end
    function catalog:newSet(name, pending)
        local set = { name = name, sets = {}, collections = {}, pending = pending }
        function set:getName() readable(self); return self.name end
        function set:getChildCollectionSets() readable(self); return self.sets end
        function set:getChildCollections() readable(self); return self.collections end
        return set
    end
    function catalog:newCollection(name, pending)
        local collection = { name = name, photos = {}, pending = pending, smart = false }
        function collection:getName() readable(self); return self.name end
        function collection:isSmartCollection() readable(self); return self.smart end
        function collection:getPhotos() readable(self); return self.photos end
        function collection:addPhotos(photos)
            assert(catalog.inWrite)
            if catalog.failAdd == self.name then error('Injected insertion failure') end
            catalog.writes = catalog.writes + 1
            for _, photo in ipairs(photos) do self.photos[#self.photos + 1] = photo end
        end
        return collection
    end
    function catalog:newPhoto(id, original, color, fallback)
        local photo = { localIdentifier = id, metadata = {
            dateTimeOriginalISO8601 = original, dateTimeISO8601 = fallback,
            colorNameForLabel = color or 'purple', label = 'Unreviewed',
        } }
        function photo:getRawMetadata(key) return self.metadata[key] end
        function photo:setRawMetadata(key, value)
            assert(catalog.inWrite)
            if catalog.failLabel == id then error('Injected label failure') end
            equal(key, 'label'); equal(value, '')
            catalog.writes = catalog.writes + 1
            self.metadata.label, self.metadata.colorNameForLabel = value, 'none'
        end
        catalog.photos[#catalog.photos + 1] = photo
        return photo
    end
    function catalog:getChildCollectionSets() return self.sets end
    function catalog:getChildCollections() return self.collections end
    function catalog:createCollectionSet(name, parent, prior)
        assert(self.inWrite); equal(parent, nil); equal(prior, false)
        if self.failCreate then error('Injected creation failure') end
        self.writes = self.writes + 1
        local set = self:newSet(name, true)
        self.sets[#self.sets + 1] = set
        return set
    end
    function catalog:createCollection(name, parent, prior)
        assert(self.inWrite); equal(prior, false)
        self.writes = self.writes + 1
        local collection = self:newCollection(name, true)
        parent.collections[#parent.collections + 1] = collection
        return collection
    end
    function catalog:withWriteAccessDo(_, callback, options)
        equal(options.asynchronous, false)
        if self.busy then return 'aborted' end
        local oldSets, oldCollections, memberships, labels = {}, {}, {}, {}
        for index, set in ipairs(self.sets) do
            oldSets[index] = set
            oldCollections[set] = {}
            for j, collection in ipairs(set.collections) do
                oldCollections[set][j] = collection
                memberships[collection] = {}
                for k, photo in ipairs(collection.photos) do memberships[collection][k] = photo end
            end
        end
        for _, photo in ipairs(self.photos) do
            labels[photo] = { photo.metadata.label, photo.metadata.colorNameForLabel }
        end
        self.inWrite = true
        local ok, message = pcall(callback)
        self.inWrite = false
        if not ok then
            self.sets = oldSets
            for set, collections in pairs(oldCollections) do set.collections = collections end
            for collection, photos in pairs(memberships) do collection.photos = photos end
            for photo, label in pairs(labels) do
                photo.metadata.label, photo.metadata.colorNameForLabel = label[1], label[2]
            end
            error(message, 0)
        end
        for _, set in ipairs(self.sets) do
            set.pending = false
            for _, collection in ipairs(set.collections) do collection.pending = false end
        end
        return 'executed'
    end
    return catalog
end

local function planFor(photos)
    local groups = Core.groupPhotos(photos)
    local names = {}
    for i in ipairs(groups) do names[i] = ' Event ' .. i .. ' ' end
    return Core.plan(groups, names)
end

test('calendar validation, leap years, and literal timezone date', function()
    equal(Core.dateFromISO('2026-09-29T00:01:00+14:00'), '2026-09-29')
    equal(Core.dateFromISO('2024-02-29'), '2024-02-29')
    for _, bad in ipairs({ '2026-02-29', '1900-02-29', '2026-04-31', '0000-01-01', '2026-00-01', '2026-01-00', '2026-09-290', 'garbage' }) do
        equal(Core.dateFromISO(bad), nil)
    end
    equal(Core.dateFromISO(nil), nil)
end)

test('no selection cannot expand to filmstrip', function()
    equal(#Core.selectedPhotos({ getTargetPhoto = function() return nil end,
        getTargetPhotos = function() error('Filmstrip must not be read') end }), 0)
end)

test('single selection uses exact SDK selection', function()
    local photo = {}
    local photos = Core.selectedPhotos({ getTargetPhoto = function() return photo end,
        getTargetPhotos = function() return { photo } end })
    equal(#photos, 1); equal(photos[1], photo)
end)

test('group order, missing dates, fallback, and corrected catalog capture time', function()
    local c = catalogFixture()
    local later = c:newPhoto(1, '2027-01-01T01:00:00', nil, '2026-12-31T01:00:00')
    local fallback = c:newPhoto(2, nil, nil, '2026-12-31T23:00:00-04:00')
    local missing = c:newPhoto(3, 'bad')
    local groups, skipped = Core.groupPhotos({ later, missing, fallback })
    equal(#groups, 2); equal(groups[1].date, '2026-12-31'); equal(groups[2].date, '2027-01-01')
    equal(skipped[1], missing)
    -- Simulates the metadata value Lightroom exposes after Edit Capture Time.
    later.metadata.dateTimeOriginalISO8601 = '2028-01-01T01:00:00'
    equal(Core.photoDate(later), '2028-01-01')
end)

test('names trimmed, prefix exact, empty/control names rejected', function()
    local c = catalogFixture()
    local groups = Core.groupPhotos({ c:newPhoto(1, '2026-09-29') })
    local plan = Core.plan(groups, { '  Evening practice  ' })
    equal(plan[1].name, '2026-09-29 ' .. Core.STATUS_PREFIX .. ' Evening practice')
    fails(function() Core.plan(groups, { ' \t ' }) end, 'non-empty')
    fails(function() Core.plan(groups, { 'event\nother' }) end, 'single-line')
    equal(Core.trim(' 　 Walk around town  '), 'Walk around town')
    equal(Core.validEvent(' 　 '), false)
end)

test('multi-year creation and all non-purple colors preserved', function()
    local c = catalogFixture()
    local colors = { 'purple', 'red', 'yellow', 'green', 'blue', 'none', 'grey', 'custom' }
    local photos = {}
    for id, color in ipairs(colors) do
        photos[id] = c:newPhoto(id, id < 5 and '2026-12-31' or '2027-01-01', color)
    end
    local result = Operations.organize(c, planFor(photos))
    equal(#c.sets, 2); equal(result.created, 2); equal(result.organized, 8); equal(result.cleared, 1)
    equal(photos[1].metadata.label, '')
    for id = 2, #photos do equal(photos[id].metadata.colorNameForLabel, colors[id]) end
end)

test('existing collection membership is idempotent; already-present purple cleared', function()
    local c = catalogFixture()
    local photo = c:newPhoto(1, '2026-09-29')
    local plan = planFor({ photo })
    Operations.organize(c, plan)
    photo.metadata.colorNameForLabel, photo.metadata.label = 'purple', 'Unreviewed'
    local result = Operations.organize(c, plan)
    equal(result.added, 0); equal(result.reused, 1); equal(result.cleared, 1)
    equal(#c.sets[1].collections[1].photos, 1)
end)

test('changed icons and other event names are left untouched', function()
    local c = catalogFixture()
    local photo = c:newPhoto(1, '2026-09-29')
    local set = c:newSet('2026'); c.sets = { set }
    set.collections = { c:newCollection('2026-09-29 ✅ Event 1') }
    Operations.organize(c, planFor({ photo }))
    equal(#set.collections, 2); equal(set.collections[1].name, '2026-09-29 ✅ Event 1')
end)

test('duplicate year sets fail before writes', function()
    local c = catalogFixture()
    c.sets = { c:newSet('2026'), c:newSet('2026') }
    fails(function() Operations.organize(c, planFor({ c:newPhoto(1, '2026-09-29') })) end, 'Multiple')
    equal(c.writes, 0)
end)

test('smart collection and nested-set conflicts fail before writes', function()
    for _, kind in ipairs({ 'smart', 'set', 'duplicate' }) do
        local c = catalogFixture()
        local plan = planFor({ c:newPhoto(1, '2026-09-29') })
        local set = c:newSet('2026'); c.sets = { set }
        if kind == 'set' then set.sets = { c:newSet(plan[1].name) }
        else
            local collection = c:newCollection(plan[1].name)
            collection.smart = kind == 'smart'
            set.collections = { collection }
            if kind == 'duplicate' then set.collections[2] = c:newCollection(plan[1].name) end
        end
        fails(function() Operations.organize(c, plan) end, kind == 'smart' and 'smart collection' or kind == 'set' and 'conflicts' or 'Multiple')
        equal(c.writes, 0)
    end
end)

test('top-level ordinary collection cannot masquerade as year set', function()
    local c = catalogFixture(); c.collections = { c:newCollection('2026') }
    fails(function() Operations.organize(c, planFor({ c:newPhoto(1, '2026-09-29') })) end, 'conflicts')
    equal(c.writes, 0)
end)

test('later insertion failure rolls back earlier dates and labels', function()
    local c = catalogFixture()
    local photos = { c:newPhoto(1, '2026-09-28'), c:newPhoto(2, '2026-09-29') }
    local plan = planFor(photos); c.failAdd = plan[2].name
    fails(function() Operations.organize(c, plan) end, 'insertion failure')
    equal(#c.sets, 0)
    for _, photo in ipairs(photos) do equal(photo.metadata.label, 'Unreviewed') end
end)

test('label failure rolls back additions to an existing collection', function()
    local c = catalogFixture()
    local first = c:newPhoto(1, '2026-09-29')
    local plan = planFor({ first }); Operations.organize(c, plan)
    local second = c:newPhoto(2, '2026-09-29'); c.failLabel = 2
    fails(function() Operations.organize(c, planFor({ first, second })) end, 'label failure')
    equal(#c.sets[1].collections[1].photos, 1); equal(second.metadata.label, 'Unreviewed')
end)

test('creation failure leaves labels untouched', function()
    local c = catalogFixture(); c.failCreate = true
    local photo = c:newPhoto(1, '2026-09-29')
    fails(function() Operations.organize(c, planFor({ photo })) end, 'creation failure')
    equal(photo.metadata.label, 'Unreviewed')
end)

test('write timeout does not return a success result', function()
    local c = catalogFixture(); c.busy = true
    fails(function() Operations.organize(c, planFor({ c:newPhoto(1, '2026-09-29') })) end, 'write access')
    equal(c.writes, 0)
end)

test('capture dates are rechecked before writing', function()
    local c = catalogFixture(); local photo = c:newPhoto(1, '2026-09-29')
    local plan = planFor({ photo }); photo.metadata.dateTimeOriginalISO8601 = '2026-09-30'
    fails(function() Operations.organize(c, plan) end, 'capture date changed')
    equal(c.writes, 0)
end)

-- Execute the real menu entry point with minimal SDK UI doubles, so cancellation,
-- the missing-date prompt, and observer-driven validation exercise the full flow.
local function runCommand(catalog, mode, missingAnswer)
    local messages, shown, props, previews = {}, {}, nil, {}
    local function findViews(view, kind, found)
        found = found or {}
        if view.kind == kind then found[#found + 1] = view end
        for _, child in ipairs(view) do findViews(child, kind, found) end
        return found
    end
    function catalog:getTargetPhoto() return self.selected and self.selected[1] end
    function catalog:getTargetPhotos() return self.selected or self.photos end
    local factory = setmetatable({}, { __index = function(_, kind)
        return function(_, args) args.kind = kind; return args end
    end })
    local sdk = {
        LrApplication = { activeCatalog = function() return catalog end },
        LrTasks = { startAsyncTask = function(fn) fn() end, pcall = pcall },
        LrFunctionContext = { callWithContext = function(_, fn) fn({}) end },
        LrView = { osFactory = function() return factory end, bind = function(key) return { key = key } end },
        LrBinding = { makePropertyTable = function()
            local values, observers = {}, {}
            props = setmetatable({}, {
                __index = function(_, key)
                    if key == 'addObserver' then
                        return function(_, name, callback) observers[name] = callback end
                    end
                    return values[key]
                end,
                __newindex = function(self, key, value)
                    values[key] = value
                    if observers[key] then observers[key](self, key, value) end
                end,
            })
            return props
        end },
        LrDialogs = {
            message = function(title, info) messages[#messages + 1] = title .. ': ' .. info end,
            confirm = function() return missingAnswer or 'ok' end,
            presentModalDialog = function(args)
                shown[#shown + 1] = args.title
                if args.title == 'Create Daily Collections' then
                    equal(props.actionEnabled, false)
                    if mode == 'cancel' then return 'cancel' end
                    local index = 1
                    while props['name' .. index] ~= nil do
                        props['name' .. index] = ' \t '
                        equal(props.actionEnabled, false)
                        props['name' .. index] = ' Event ' .. index .. ' '
                        index = index + 1
                    end
                    equal(props.actionEnabled, true)
                    equal(args.actionBinding.enabled.key, 'actionEnabled')
                    if mode == 'preview-cancel' then
                        for _, button in ipairs(findViews(args.contents, 'push_button')) do
                            button.action()
                            equal(props.actionEnabled, true)
                            for i = 1, index - 1 do equal(props['name' .. i], ' Event ' .. i .. ' ') end
                        end
                        return 'cancel'
                    end
                elseif args.title:find('Photos from ', 1, true) then
                    local photos = {}
                    for _, view in ipairs(findViews(args.contents, 'catalog_photo')) do
                        photos[#photos + 1] = view.photo
                    end
                    previews[#previews + 1] = { title = args.title, photos = photos }
                end
                return 'ok'
            end,
        },
    }
    _G.import = function(name) assert(sdk[name], name); return sdk[name] end
    dofile('DailyCollections.lrplugin/CreateDailyCollections.lua')
    _G.import = nil
    return messages, shown, previews
end

test('menu command cancellation leaves catalog and purple labels unchanged', function()
    local c = catalogFixture(); local photo = c:newPhoto(1, '2026-09-29'); c.selected = { photo }
    local messages, shown = runCommand(c, 'cancel')
    equal(c.writes, 0); equal(photo.metadata.label, 'Unreviewed'); equal(#messages, 0); equal(#shown, 1)
end)

test('menu command no-selection and all-missing-date paths never write', function()
    local c = catalogFixture(); c:newPhoto(1, '2026-09-29')
    local messages, shown = runCommand(c)
    assert(messages[1]:find('Select one or more photos', 1, true)); equal(#shown, 0); equal(c.writes, 0)
    c.selected = { c:newPhoto(2, nil) }
    messages, shown = runCommand(c)
    assert(messages[1]:find('No usable capture dates', 1, true)); equal(#shown, 0); equal(c.writes, 0)
end)

test('menu command missing-date cancellation and successful skip', function()
    local c = catalogFixture()
    local dated, missing = c:newPhoto(1, '2026-09-29'), c:newPhoto(2, nil)
    c.selected = { dated, missing }
    runCommand(c, 'create', 'cancel'); equal(c.writes, 0)
    local messages, shown = runCommand(c, 'create', 'ok')
    equal(#messages, 0); equal(shown[2], 'Daily Collections complete')
    equal(dated.metadata.label, ''); equal(missing.metadata.label, 'Unreviewed')
end)

test('menu command displays error and never success after failed transaction', function()
    local c = catalogFixture(); c.failLabel = 1
    c.selected = { c:newPhoto(1, '2026-09-29') }
    local messages, shown = runCommand(c, 'create')
    assert(messages[1]:find('Injected label failure', 1, true)); equal(#shown, 1); equal(#c.sets, 0)
end)

test('nine samples span capture order without changing input order', function()
    local c = catalogFixture()
    local photos = {}
    for id = 17, 1, -1 do
        photos[#photos + 1] = c:newPhoto(id, string.format('2026-09-29T12:%02d:00', id))
    end
    local samples = Core.samplePhotos(photos)
    equal(#samples, 9)
    for i, photo in ipairs(samples) do equal(photo.localIdentifier, 2 * i - 1) end
    equal(photos[1].localIdentifier, 17); equal(photos[17].localIdentifier, 1)
end)

test('small-day samples include every photo and handle equal capture times', function()
    equal(#Core.samplePhotos({}), 0)
    for count = 1, 9 do
        local c = catalogFixture(); local photos = {}
        for id = count, 1, -1 do photos[#photos + 1] = c:newPhoto(id, '2026-09-29T12:00:00') end
        local samples = Core.samplePhotos(photos)
        equal(#samples, count)
        for id, photo in ipairs(samples) do equal(photo.localIdentifier, id) end
    end
end)

test('previews use each date selection and preserve names through cancellation', function()
    local c = catalogFixture(); local photos = {}
    for id = 1, 17 do
        photos[#photos + 1] = c:newPhoto(id, string.format('2026-09-29T12:%02d:00', id))
    end
    photos[#photos + 1] = c:newPhoto(18, '2026-09-30T12:00:00')
    c.selected = photos
    local messages, shown, previews = runCommand(c, 'preview-cancel')
    equal(#messages, 0); equal(#shown, 3); equal(#previews, 2)
    equal(previews[1].title, 'Photos from 2026-09-29'); equal(#previews[1].photos, 9)
    equal(previews[2].title, 'Photos from 2026-09-30'); equal(previews[2].photos[1], photos[18])
    equal(c.writes, 0)
    for _, photo in ipairs(photos) do equal(photo.metadata.label, 'Unreviewed') end
end)

print(passed .. ' tests passed')
