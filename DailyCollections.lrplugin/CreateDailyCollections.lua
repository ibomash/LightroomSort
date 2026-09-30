local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'
local Core = require 'Core'
local Operations = require 'CatalogOperations'

local function showPhotoPreview(group)
    local factory = LrView.osFactory()
    local samples = Core.samplePhotos(group.photos)
    local grid = { spacing = 10 }
    for first = 1, #samples, 3 do
        local row = { spacing = 10 }
        for index = first, math.min(first + 2, #samples) do
            row[#row + 1] = factory:catalog_photo {
                photo = samples[index], width = 180, height = 150,
            }
        end
        grid[#grid + 1] = factory:row(row)
    end
    LrDialogs.presentModalDialog {
        title = 'Photos from ' .. group.date,
        actionVerb = 'Back to Naming', cancelVerb = '< exclude >',
        contents = factory:column {
            spacing = 14,
            factory:static_text {
                title = #samples .. ' of ' .. #group.photos .. ' selected photos · in capture-time order',
            },
            factory:column(grid),
        },
    }
end

local function showNamingDialog(context, groups)
    local props = LrBinding.makePropertyTable(context)
    local factory = LrView.osFactory()
    local rows = { spacing = 14, margin = 14 }
    local previewOpen = false
    rows[#rows + 1] = factory:row {
        spacing = 16,
        factory:static_text { title = 'Date', width = 100 },
        factory:static_text { title = 'Photos', width = 75, alignment = 'right' },
        factory:static_text { title = 'Event name', width = 340 },
        factory:spacer { width = 85 },
    }
    local function refresh()
        local valid = true
        for index in ipairs(groups) do
            local event = props['name' .. index]
            if not Core.validEvent(event) then valid = false end
        end
        props.actionEnabled = valid
    end
    for index, group in ipairs(groups) do
        local key = 'name' .. index
        props[key] = ''
        props:addObserver(key, refresh)
        rows[#rows + 1] = factory:row {
            spacing = 16,
            factory:static_text { title = group.date, width = 100 },
            factory:static_text { title = tostring(#group.photos), width = 75, alignment = 'right' },
            factory:edit_field {
                value = LrView.bind(key), width = 340,
                immediate = true, wraps = false,
            },
            factory:push_button {
                title = 'Preview…', width = 85,
                action = function()
                    if previewOpen then return end
                    previewOpen = true
                    -- Button callbacks are UI events; metadata reads belong in a task.
                    LrTasks.startAsyncTask(function()
                        local ok, message = LrTasks.pcall(function() showPhotoPreview(group) end)
                        previewOpen = false
                        if not ok then
                            LrDialogs.message('Could not show photo preview', tostring(message), 'warning')
                        end
                    end)
                end,
            },
        }
    end
    refresh()
    local contents = factory:column {
        bind_to_object = props, spacing = 14,
        factory:static_text { title = 'Enter one event name for each date.' },
        factory:scrolled_view {
            width = 705, height = math.min(380, math.max(100, 62 + #groups * 38)),
            horizontal_scroller = false, vertical_scroller = true,
            factory:column(rows),
        },
        factory:static_text { title = 'Purple “Unreviewed” labels will be cleared after organizing.' },
    }
    if LrDialogs.presentModalDialog {
        title = 'Create Daily Collections', contents = contents,
        actionVerb = 'Create Collections', cancelVerb = 'Cancel',
        actionBinding = { enabled = { bind_to_object = props, key = 'actionEnabled' } },
    } ~= 'ok' then return nil end
    local names = {}
    for index in ipairs(groups) do names[index] = props['name' .. index] end
    return Core.plan(groups, names)
end

local function main(context)
    local catalog = LrApplication.activeCatalog()
    -- Snapshot the actual selection once; later selection changes cannot expand it.
    local photos = Core.selectedPhotos(catalog)
    if #photos == 0 then
        LrDialogs.message('Daily Collections', 'Select one or more photos before running Daily Collections.', 'info')
        return
    end
    local groups, missing = Core.groupPhotos(photos)
    if #groups == 0 then
        LrDialogs.message('No usable capture dates', 'None of the selected photos has a usable capture date. No changes were made.', 'warning')
        return
    end
    if #missing > 0 then
        local answer = LrDialogs.confirm('Some photos cannot be organized',
            #missing .. ' selected photos do not have a usable capture date. They will be left unchanged.',
            'Continue with remaining ' .. (#photos - #missing) .. ' photos', 'Cancel')
        if answer ~= 'ok' then return end
    end
    local plan = showNamingDialog(context, groups)
    if not plan then return end
    Operations.preflight(catalog, plan)
    local result = Operations.organize(catalog, plan)
    local lines = {}
    for _, item in ipairs(result.dates) do
        lines[#lines + 1] = item.date .. '\n' .. item.count .. ' photos → ' .. item.event
    end
    lines[#lines + 1] = result.organized .. ' photos organized\n'
        .. result.added .. ' newly added (' .. (result.organized - result.added) .. ' already present)\n'
        .. result.cleared .. ' purple labels cleared\n'
        .. result.created .. ' collections created; ' .. result.reused .. ' reused'
    if #missing > 0 then lines[#lines + 1] = #missing .. ' photos skipped (missing capture date)' end
    local factory = LrView.osFactory()
    LrDialogs.presentModalDialog {
        title = 'Daily Collections complete', actionVerb = 'Done', cancelVerb = '< exclude >',
        contents = factory:scrolled_view {
            width = 620, height = math.min(420, math.max(160, #result.dates * 55 + 110)),
            horizontal_scroller = false,
            factory:static_text { title = table.concat(lines, '\n\n'), width = 580 },
        },
    }
end

LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext('DailyCollections', function(context)
        -- LrTasks.pcall supports SDK yields; ordinary Lua pcall does not.
        local ok, message = LrTasks.pcall(function() main(context) end)
        if not ok then
            LrDialogs.message('Daily Collections could not finish', tostring(message), 'critical')
        end
    end)
end)
