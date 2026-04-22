local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local PlaceID = game.PlaceId

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("Vicious Hopper", "DarkTheme")

local MainTab = Window:NewTab("Main")
local WebhookTab = Window:NewTab("Webhook")
local ServerTab = Window:NewTab("Server")
local UiTab = Window:NewTab("UI")

local RuntimeSection = MainTab:NewSection("Runtime")
local ControlSection = MainTab:NewSection("Controls")
local WebhookSection = WebhookTab:NewSection("Webhook Settings")
local WebhookTestSection = WebhookTab:NewSection("Webhook Tests")
local ServerSection = ServerTab:NewSection("Server Settings")
local UtilitySection = ServerTab:NewSection("Utilities")
local UiSection = UiTab:NewSection("UI")

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

local function updateLabel(labelObject, text)
    pcall(function()
        labelObject:UpdateLabel(text)
    end)
end

local StatusLabel = RuntimeSection:NewLabel("Status: Idle")
local ResultLabel = RuntimeSection:NewLabel("Last Result: None")
local JobLabel = RuntimeSection:NewLabel("Current JobId: " .. tostring(game.JobId))
local WebhookStateLabel = RuntimeSection:NewLabel("Webhook State: Ready")
local SettingsLabel = RuntimeSection:NewLabel("Webhook: Enabled | Hopper: Disabled")

local function refreshInfo()
    updateLabel(JobLabel, "Current JobId: " .. tostring(game.JobId))
    updateLabel(SettingsLabel, "Webhook: " .. (Settings.WebhookEnabled and "Enabled" or "Disabled") .. " | Hopper: " .. (Settings.Enabled and "Enabled" or "Disabled"))
end

local function getRequestFunction()
    return request
        or http_request
        or (syn and syn.request)
        or (fluxus and fluxus.request)
end

local function ensureFolder()
    pcall(function()
        if isfolder and makefolder and not isfolder(FOLDER_NAME) then
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
        if writefile then
            writefile(SAVE_FILE, HttpService:JSONEncode(AllIDs))
        end
    end)
end

local function loadServerList()
    local success, data = pcall(function()
        if readfile then
            return HttpService:JSONDecode(readfile(SAVE_FILE))
        end
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
    lastWebhookJobId = nil
end

local function resetServerListIfHourChanged()
    if not Settings.ResetVisitedHourly then
        return
    end

    local currentHour = getCurrentHour()

    if tonumber(AllIDs[1]) ~= currentHour then
        pcall(function()
            if delfile then
                delfile(SAVE_FILE)
            end
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

        if site and site.data then
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
        else
            task.wait(0.25)
        end

        task.wait(0.1)
    end

    return nil
end

local function hopServer()
    resetServerListIfHourChanged()

    local serverId = findAvailableServer(Settings.MaxPages)
    if not serverId then
        updateLabel(StatusLabel, "Status: No new server found")
        return false
    end

    markServerVisited(serverId)
    updateLabel(StatusLabel, "Status: Teleporting")

    local success = pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceID, serverId, LocalPlayer)
    end)

    return success
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
        updateLabel(WebhookStateLabel, "Webhook State: Disabled")
        return false
    end

    if not Settings.WebhookURL or Settings.WebhookURL == "" then
        updateLabel(WebhookStateLabel, "Webhook State: Missing URL")
        return false
    end

    local requestFunction = getRequestFunction()
    if not requestFunction then
        updateLabel(WebhookStateLabel, "Webhook State: No request function")
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

    if success then
        updateLabel(WebhookStateLabel, "Webhook State: Sent (" .. tostring(isVicious) .. ")")
    else
        updateLabel(WebhookStateLabel, "Webhook State: Failed")
    end

    return success
end

local function startLoop()
    if loopRunning then
        return
    end

    loopRunning = true

    task.spawn(function()
        while Settings.Enabled do
            refreshInfo()
            updateLabel(JobLabel, "Current JobId: " .. tostring(game.JobId))

            local currentJobId = game.JobId

            if lastWebhookJobId ~= currentJobId then
                updateLabel(StatusLabel, "Status: Scanning server")
                local isVicious = scanViciousForDuration(Settings.CheckDuration, Settings.CheckInterval)

                updateLabel(ResultLabel, "Last Result: " .. tostring(isVicious))
                sendDiscordWebhook(isVicious)

                lastWebhookJobId = currentJobId
            else
                updateLabel(StatusLabel, "Status: Waiting for new server")
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

        updateLabel(StatusLabel, "Status: Stopped")
        refreshInfo()
        loopRunning = false
    end)
end

ensureFolder()
loadServerList()
refreshInfo()

ControlSection:NewToggle("Enable Hopper", "Start or stop the hopper", function(state)
    Settings.Enabled = state
    refreshInfo()

    if state then
        updateLabel(StatusLabel, "Status: Starting")
        startLoop()
    else
        updateLabel(StatusLabel, "Status: Stopping")
    end
end)

ControlSection:NewButton("Send Current Server Status", "Send one webhook for this server", function()
    local isVicious = hasVicious()
    updateLabel(ResultLabel, "Last Result: " .. tostring(isVicious))
    sendDiscordWebhook(isVicious)
end)

ControlSection:NewButton("Reset Webhook Lock", "Allow webhook resend on current server", function()
    lastWebhookJobId = nil
    updateLabel(StatusLabel, "Status: Webhook lock reset")
end)

WebhookSection:NewToggle("Enable Webhook", "Enable or disable webhook sending", function(state)
    Settings.WebhookEnabled = state
    refreshInfo()
end)

WebhookSection:NewTextBox("Webhook URL", "Paste your Discord webhook URL", function(txt)
    Settings.WebhookURL = tostring(txt or "")
end)

WebhookSection:NewButton("Use Default Webhook URL", "Restore the default webhook URL", function()
    Settings.WebhookURL = "https://discord.com/api/webhooks/1496537416356335626/uxX18rqqSu6JcIo4QeXXF-pXijzjq2P-bpEFUOMMeUZfX0m8AxXsVnvjce3rv-goY3tw"
    updateLabel(WebhookStateLabel, "Webhook State: Default URL restored")
end)

WebhookTestSection:NewButton("Send True Test", "Send a green webhook", function()
    sendDiscordWebhook(true)
end)

WebhookTestSection:NewButton("Send False Test", "Send a red webhook", function()
    sendDiscordWebhook(false)
end)

ServerSection:NewSlider("Check Duration", "How long to scan each server", 15, 1, function(value)
    Settings.CheckDuration = tonumber(value) or Settings.CheckDuration
end)

ServerSection:NewTextBox("Check Interval", "Example: 0.5", function(txt)
    local num = tonumber(txt)
    if num and num > 0 then
        Settings.CheckInterval = num
    end
end)

ServerSection:NewSlider("Retry Delay", "Delay when no server is found", 15, 1, function(value)
    Settings.RetryDelay = tonumber(value) or Settings.RetryDelay
end)

ServerSection:NewSlider("Max Pages", "How many server pages to scan", 30, 1, function(value)
    Settings.MaxPages = tonumber(value) or Settings.MaxPages
end)

ServerSection:NewToggle("Reset Visited Hourly", "Reset visited servers every hour", function(state)
    Settings.ResetVisitedHourly = state
end)

UtilitySection:NewButton("Reset Visited Servers", "Clear visited server list", function()
    resetVisitedServers()
    updateLabel(StatusLabel, "Status: Visited servers reset")
end)

UtilitySection:NewButton("Reload Visited File", "Reload local visited server file", function()
    loadServerList()
    updateLabel(StatusLabel, "Status: Visited file reloaded")
end)

UtilitySection:NewButton("Force Hop Now", "Try to hop immediately", function()
    task.spawn(function()
        hopServer()
    end)
end)

UiSection:NewKeybind("Toggle UI", "Show or hide the UI", Enum.KeyCode.RightControl, function()
    Library:ToggleUI()
end)

UiSection:NewDropdown("Theme", "Change UI theme", {
    "LightTheme",
    "DarkTheme",
    "GrapeTheme",
    "BloodTheme",
    "Ocean",
    "Midnight",
    "Sentinel",
    "Synapse"
}, function(currentTheme)
    local success, newLibrary = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
    end)

    if success and newLibrary then
        -- Theme switching is not dynamically exposed reliably by Kavo,
        -- so this dropdown is informational for future extension.
        updateLabel(StatusLabel, "Status: Selected theme " .. tostring(currentTheme))
    end
end)
