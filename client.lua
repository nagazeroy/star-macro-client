local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local PlaceID = game.PlaceId

local function getRequestFunction()
    return request
        or http_request
        or (syn and syn.request)
        or (fluxus and fluxus.request)
end

local requestFunction = getRequestFunction()
if not requestFunction then
    return
end

local librarySource = requestFunction({
    Method = "GET",
    Url = "https://wednesday.wtf/library.lua"
})

local library = loadstring(librarySource.Body)()

local window = library:new_window("vicious hopper", nil, nil)

local main_tab = window:new_tab("main")
local settings_tab = window:new_tab("settings")

library:apply_settings(settings_tab)

local automation_group = main_tab:new_group("automation", false)
local webhook_group = main_tab:new_group("webhook", true)
local utility_group = main_tab:new_group("utility", false)

local FOLDER_NAME = "star_macro"
local SAVE_FILE = FOLDER_NAME .. "/NotSameServers.json"

local Settings = {
    Enabled = false,
    WebhookEnabled = true,
    WebhookURL = "https://discord.com/api/webhooks/1496537416356335626/uxX18rqqSu6JcIo4QeXXF-pXijzjq2P-bpEFUOMMeUZfX0m8AxXsVnvjce3rv-goY3tw",
    CheckDuration = 3,
    CheckInterval = 0.5,
    RetryDelay = 2,
    MaxPages = 10,
    ResetVisitedHourly = true
}

local AllIDs = {}
local VisitedIDs = {}
local foundAnything = ""
local lastWebhookJobId = nil
local loopRunning = false

local function ensureFolder()
    pcall(function()
        if not isfolder(FOLDER_NAME) then
            makefolder(FOLDER_NAME)
        end
    end)
end

local function getCurrentHour()
    return os.date("!*t").hour
end

local function rebuildVisitedMap()
    VisitedIDs = {}
    for i = 2, #AllIDs do
        VisitedIDs[tostring(AllIDs[i])] = true
    end
end

local function saveServerList()
    pcall(function()
        writefile(SAVE_FILE, HttpService:JSONEncode(AllIDs))
    end)
end

local function loadServerList()
    local success, data = pcall(function()
        return HttpService:JSONDecode(readfile(SAVE_FILE))
    end)

    if success and type(data) == "table" and #data >= 1 then
        AllIDs = data
    else
        AllIDs = { getCurrentHour() }
        saveServerList()
    end

    rebuildVisitedMap()
end

local function resetVisitedServers()
    foundAnything = ""
    AllIDs = { getCurrentHour() }
    rebuildVisitedMap()
    saveServerList()
end

local function resetServerListIfHourChanged()
    if not Settings.ResetVisitedHourly then
        return
    end

    local currentHour = getCurrentHour()

    if tonumber(AllIDs[1]) ~= currentHour then
        pcall(function()
            delfile(SAVE_FILE)
        end)

        AllIDs = { currentHour }
        saveServerList()
        rebuildVisitedMap()
        foundAnything = ""
    end
end

local function hasServerBeenVisited(serverId)
    return VisitedIDs[tostring(serverId)] == true
end

local function markServerVisited(serverId)
    serverId = tostring(serverId)

    if not VisitedIDs[serverId] then
        VisitedIDs[serverId] = true
        table.insert(AllIDs, serverId)
        saveServerList()
    end
end

local function getServerPage(cursor)
    local url = "https://games.roblox.com/v1/games/" .. PlaceID .. "/servers/Public?sortOrder=Asc&limit=100"

    if cursor and cursor ~= "" then
        url = url .. "&cursor=" .. cursor
    end

    local success, result = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)

    if success and result and result.data then
        return result
    end

    return nil
end

local function findAvailableServer(maxPages)
    local currentJobId = game.JobId
    local cursor = foundAnything

    for _ = 1, maxPages do
        local site = getServerPage(cursor)
        if not site or not site.data then
            task.wait(0.25)
        else
            for _, server in ipairs(site.data) do
                local serverId = tostring(server.id)
                local playing = tonumber(server.playing) or 0
                local maxPlayers = tonumber(server.maxPlayers) or 0

                if serverId ~= currentJobId and playing < maxPlayers and not hasServerBeenVisited(serverId) then
                    foundAnything = site.nextPageCursor or ""
                    return serverId
                end
            end

            if site.nextPageCursor and site.nextPageCursor ~= "null" then
                cursor = site.nextPageCursor
                foundAnything = cursor
            else
                foundAnything = ""
                break
            end
        end

        task.wait(0.1)
    end

    return nil
end

local function hopServer()
    resetServerListIfHourChanged()

    local serverId = findAvailableServer(Settings.MaxPages)
    if not serverId then
        return false
    end

    markServerVisited(serverId)

    pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceID, serverId, LocalPlayer)
    end)

    return true
end

local function hasVicious()
    local particles = workspace:FindFirstChild("Particles")
    if not particles then
        return false
    end

    return particles:FindFirstChild("Vicious") ~= nil
end

local function scanViciousForDuration(duration, interval)
    local startTime = tick()

    while tick() - startTime < duration do
        if hasVicious() then
            return true
        end

        task.wait(interval)
    end

    return false
end

local function sendDiscordWebhook(isVicious)
    if not Settings.WebhookEnabled then
        return false
    end

    if not Settings.WebhookURL or Settings.WebhookURL == "" then
        return false
    end

    local color = isVicious and 65280 or 16711680
    local embed = {
        title = "Vicious Status",
        description = string.format("`Vicious : %s`", tostring(isVicious)),
        color = color,
        fields = {
            {
                name = "Player",
                value = LocalPlayer and LocalPlayer.Name or "Unknown",
                inline = true
            },
            {
                name = "PlaceId",
                value = tostring(PlaceID),
                inline = true
            },
            {
                name = "JobId",
                value = tostring(game.JobId),
                inline = false
            }
        },
        footer = {
            text = os.date("!%Y-%m-%d %H:%M:%S UTC")
        }
    }

    if isVicious then
        table.insert(embed.fields, {
            name = "Link",
            value = string.format("roblox://placeID=%s&gameInstanceId=%s", tostring(PlaceID), tostring(game.JobId)),
            inline = false
        })
    end

    local body = HttpService:JSONEncode({
        embeds = { embed }
    })

    local success = pcall(function()
        requestFunction({
            Url = Settings.WebhookURL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = body
        })
    end)

    return success
end

local function startLoop()
    if loopRunning then
        return
    end

    loopRunning = true

    task.spawn(function()
        while Settings.Enabled do
            local currentJobId = game.JobId

            if lastWebhookJobId ~= currentJobId then
                local isVicious = scanViciousForDuration(Settings.CheckDuration, Settings.CheckInterval)
                sendDiscordWebhook(isVicious)
                lastWebhookJobId = currentJobId
            end

            if not Settings.Enabled then
                break
            end

            local hopped = hopServer()

            if not hopped then
                task.wait(Settings.RetryDelay)
            else
                task.wait(0.2)
            end
        end

        loopRunning = false
    end)
end

ensureFolder()
loadServerList()

automation_group:new_checkbox("enable_hopper", {
    text = "Enable Hopper",
    default = Settings.Enabled,
    callback = function(state)
        Settings.Enabled = state
        if state then
            startLoop()
        end
    end
})

automation_group:new_slider("check_duration", {
    text = "Check Duration",
    min = 0,
    max = 15,
    default = Settings.CheckDuration,
    decimals = 1,
    suffix = " sec",
    callback = function(state)
        Settings.CheckDuration = tonumber(state) or Settings.CheckDuration
    end
})

automation_group:new_slider("check_interval", {
    text = "Check Interval",
    min = 0.1,
    max = 5,
    default = Settings.CheckInterval,
    decimals = 1,
    suffix = " sec",
    callback = function(state)
        Settings.CheckInterval = tonumber(state) or Settings.CheckInterval
    end
})

automation_group:new_slider("retry_delay", {
    text = "Retry Delay",
    min = 1,
    max = 15,
    default = Settings.RetryDelay,
    decimals = 0,
    suffix = " sec",
    callback = function(state)
        Settings.RetryDelay = tonumber(state) or Settings.RetryDelay
    end
})

automation_group:new_slider("max_pages", {
    text = "Max Pages",
    min = 1,
    max = 30,
    default = Settings.MaxPages,
    decimals = 0,
    callback = function(state)
        Settings.MaxPages = tonumber(state) or Settings.MaxPages
    end
})

automation_group:new_checkbox("reset_hourly", {
    text = "Reset Visited Hourly",
    default = Settings.ResetVisitedHourly,
    callback = function(state)
        Settings.ResetVisitedHourly = state
    end
})

webhook_group:new_checkbox("enable_webhook", {
    text = "Enable Webhook",
    default = Settings.WebhookEnabled,
    callback = function(state)
        Settings.WebhookEnabled = state
    end
})

webhook_group:new_textbox("webhook_url", {
    text = "Webhook URL",
    default = Settings.WebhookURL,
    callback = function(state)
        Settings.WebhookURL = tostring(state or "")
    end
})

webhook_group:new_button({
    text = "Send True Test",
    callback = function()
        sendDiscordWebhook(true)
    end
})

webhook_group:new_button({
    text = "Send False Test",
    callback = function()
        sendDiscordWebhook(false)
    end
})

webhook_group:new_button({
    text = "Send Current Server Status",
    callback = function()
        local isVicious = hasVicious()
        sendDiscordWebhook(isVicious)
    end
})

utility_group:new_button({
    text = "Reset Visited Servers",
    callback = function()
        resetVisitedServers()
        lastWebhookJobId = nil
    end
})

utility_group:new_button({
    text = "Reload Visited File",
    callback = function()
        loadServerList()
    end
})
