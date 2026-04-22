local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local PlaceID = game.PlaceId
local JobID = game.JobId

local FOLDER_NAME = "star_macro"
local SAVE_FILE = FOLDER_NAME .. "/NotSameServers.json"

local WEBHOOK_PROXY_URL = "https://bloxrank.net/api/webhook/"
local DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/1496537416356335626/uxX18rqqSu6JcIo4QeXXF-pXijzjq2P-bpEFUOMMeUZfX0m8AxXsVnvjce3rv-goY3tw"

local AllIDs = {}
local VisitedIDs = {}
local foundAnything = ""

local function ensureFolder()
    if not isfolder(FOLDER_NAME) then
        makefolder(FOLDER_NAME)
    end
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
    writefile(SAVE_FILE, HttpService:JSONEncode(AllIDs))
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

local function resetServerListIfHourChanged()
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

    if success and result then
        return result
    end

    return nil
end

local function findAvailableServer(maxPages)
    local cursor = foundAnything

    for page = 1, maxPages do
        local site = getServerPage(cursor)

        if not site or not site.data then
            warn("[DEBUG] Failed to load server page:", page)
            task.wait(0.5)
            continue
        end

        for _, server in ipairs(site.data) do
            local serverId = tostring(server.id)
            local playing = tonumber(server.playing) or 0
            local maxPlayers = tonumber(server.maxPlayers) or 0

            if serverId ~= JobID and playing < maxPlayers and not hasServerBeenVisited(serverId) then
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

        task.wait(0.15)
    end

    return nil
end

local function Teleport(maxPages)
    resetServerListIfHourChanged()

    local serverId = findAvailableServer(maxPages or 10)

    if not serverId then
        warn("[DEBUG] Failed to find server")
        return false
    end

    markServerVisited(serverId)

    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceID, serverId, LocalPlayer)
    end)

    if not success then
        warn("[DEBUG] Teleport failed:", err)
        return false
    end

    return true
end

local function hasVicious()
    local particles = workspace:FindFirstChild("Particles")
    if not particles then
        return false
    end

    return particles:FindFirstChild("Vicious") ~= nil
end

local function getRequestFunction()
    return request
        or http_request
        or (syn and syn.request)
        or (fluxus and fluxus.request)
end

local function postJson(url, body)
    local req = getRequestFunction()

    if req then
        return req({
            Url = url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = body
        })
    else
        return HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
    end
end

local function buildServerLinks()
    local robloxProtocol = string.format("roblox://placeID=%s&gameInstanceId=%s", tostring(PlaceID), tostring(JobID))
    local webLink = string.format("https://www.roblox.com/games/start?placeId=%s&gameInstanceId=%s", tostring(PlaceID), tostring(JobID))
    local gamePage = string.format("https://www.roblox.com/games/%s", tostring(PlaceID))

    return robloxProtocol, webLink, gamePage
end

local function sendViciousWebhook()
    local robloxProtocol, webLink, gamePage = buildServerLinks()

    local payload = {
        WebhookURL = DISCORD_WEBHOOK_URL,
        WebhookData = {
            ["Event"] = "Vicious found",
            ["Vicious found ?"] = true,
            ["Player"] = LocalPlayer and LocalPlayer.Name or "Unknown",
            ["PlaceId"] = tostring(PlaceID),
            ["JobId"] = tostring(JobID),
            ["Join (roblox protocol)"] = robloxProtocol,
            ["Join (web)"] = webLink,
            ["Game page"] = gamePage
        }
    }

    local body = HttpService:JSONEncode(payload)

    local success, response = pcall(function()
        return postJson(WEBHOOK_PROXY_URL, body)
    end)

    if success then
        print("[DEBUG] Webhook sent.")
        return true
    else
        warn("[DEBUG] Webhook failed:", response)
        return false
    end
end

ensureFolder()
loadServerList()

while true do
    local is_vicious = hasVicious()
    print("[DEBUG] Vicious:", is_vicious)

    if is_vicious then
        print("[DEBUG] VICIOUS FOUND")
        
        
    end
    sendViciousWebhook()
    wait(2)
    local ok = Teleport(10)
    if not ok then
        task.wait(1)
    end

    task.wait(1)
end
