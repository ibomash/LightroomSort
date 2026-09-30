-- No SDK dependencies: date validation and planning can be tested outside Lightroom.
local Core = {}
Core.STATUS_PREFIX = '❌⭐⌫🗺🌃🖨☀️✅'
local UNICODE_SPACES = {
    ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', '　',
}

function Core.trim(value)
    if type(value) ~= 'string' then return '' end
    -- Lua 5.1 patterns operate on bytes; trim UTF-8 spaces as complete strings.
    local previous
    repeat
        previous = value
        value = value:gsub('^%s+', ''):gsub('%s+$', '')
        for _, space in ipairs(UNICODE_SPACES) do
            value = value:gsub('^' .. space, ''):gsub(space .. '$', '')
        end
    until value == previous
    return value
end

function Core.dateFromISO(value)
    if type(value) ~= 'string' then return nil end
    local year, month, day = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)')
    if not year then return nil end
    -- Accept a date alone or an ISO datetime; never convert its timezone.
    if #value > 10 and value:sub(11, 11) ~= 'T' then return nil end
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if year < 1 or month < 1 or month > 12 then return nil end
    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then days[2] = 29 end
    if day < 1 or day > days[month] then return nil end
    return value:sub(1, 10)
end

function Core.photoDate(photo)
    -- These are catalog metadata, including Lightroom's Edit Capture Time changes.
    return Core.dateFromISO(photo:getRawMetadata('dateTimeOriginalISO8601'))
        or Core.dateFromISO(photo:getRawMetadata('dateTimeISO8601'))
end

function Core.selectedPhotos(catalog)
    if not catalog:getTargetPhoto() then return {} end
    return catalog:getTargetPhotos()
end

function Core.groupPhotos(photos)
    local byDate, dates, missing = {}, {}, {}
    for _, photo in ipairs(photos) do
        local date = Core.photoDate(photo)
        if date then
            if not byDate[date] then
                byDate[date] = {}
                dates[#dates + 1] = date
            end
            local group = byDate[date]
            group[#group + 1] = photo
        else
            missing[#missing + 1] = photo
        end
    end
    table.sort(dates)
    local groups = {}
    for _, date in ipairs(dates) do
        groups[#groups + 1] = { date = date, year = date:sub(1, 4), photos = byDate[date] }
    end
    return groups, missing
end

function Core.samplePhotos(photos)
    -- Sort a copy: previewing must not change the selection or placement order.
    local ordered = {}
    for index, photo in ipairs(photos) do
        local iso = photo:getRawMetadata('dateTimeOriginalISO8601')
        if not Core.dateFromISO(iso) then iso = photo:getRawMetadata('dateTimeISO8601') end
        ordered[#ordered + 1] = {
            photo = photo,
            time = type(iso) == 'string' and iso:sub(1, 19) or '',
            id = photo.localIdentifier or index,
        }
    end
    table.sort(ordered, function(a, b)
        if a.time == b.time then return a.id < b.id end
        return a.time < b.time
    end)
    local count = math.min(9, #ordered)
    local samples = {}
    for index = 1, count do
        -- Include both endpoints, with evenly spaced indices in between.
        local position = count == 1 and 1
            or 1 + math.floor((index - 1) * (#ordered - 1) / (count - 1) + 0.5)
        samples[#samples + 1] = ordered[position].photo
    end
    return samples
end

function Core.collectionName(date, event)
    return date .. ' ' .. Core.STATUS_PREFIX .. ' ' .. Core.trim(event)
end

function Core.validEvent(value)
    local name = Core.trim(value)
    return name ~= '' and not name:find('%c')
end

function Core.plan(groups, names)
    local plan = {}
    for index, group in ipairs(groups) do
        local event = Core.trim(names[index])
        if not Core.validEvent(event) then
            error('Enter a non-empty, single-line event name for ' .. group.date .. '.', 0)
        end
        plan[#plan + 1] = {
            date = group.date, year = group.year, photos = group.photos,
            event = event, name = Core.collectionName(group.date, event),
        }
    end
    return plan
end

return Core
