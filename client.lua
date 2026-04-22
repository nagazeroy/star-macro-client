local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local PlaceID = game.PlaceId

local WEBHOOK_URL = "https://discord.com/api/webhooks/1496537416356335626/uxX18rqqSu6JcIo4QeXXF-pXijzjq2P-bpEFUOMMeUZfX0m8AxXsVnvjce3rv-goY3tw"

local FOLDER_NAME = "star_macro"
local SAVE_FILE = FOLDER_NAME .. "/NotSameServers.json"

local CHECK_DURATION = 3      -- temps total de check dans le serveur
local CHECK_INTERVAL = 0.5    -- fréquence de check pendant CHECK_DURATION
local RETRY_DELAY = 2         -- attente si aucun serveur trouvé
local MAX_PAGES = 10          -- nombre de pages max à scanner

local AllIDs = {}
local VisitedIDs = {}
local foundAnything = ""

local lastWebhookJobId = nil

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
        print("[DEBUG] Server list reset")
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

    for page = 1, maxPages do
        print("[DEBUG] Scanning page:", page)

        local site = getServerPage(cursor)
        if not site or not site.data then
            warn("[DEBUG] Failed to load server page:", page)
            task.wait(0.3)
            continue
        end

        for _, server in ipairs(site.data) do
            local serverId = tostring(server.id)
            local playing = tonumber(server.playing) or 0
            local maxPlayers = tonumber(server.maxPlayers) or 0

            if serverId ~= currentJobId and playing < maxPlayers and not hasServerBeenVisited(serverId) then
                foundAnything = site.nextPageCursor or ""
                print("[DEBUG] Found server:", serverId, "(" .. playing .. "/" .. maxPlayers .. ")")
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

        task.wait(0.1)
    end

    return nil
end

local function hopServer()
    resetServerListIfHourChanged()

    local serverId = findAvailableServer(MAX_PAGES)
    if not serverId then
        warn("[DEBUG] Failed to find server to hop")
        return false
    end

    markServerVisited(serverId)
    print("[DEBUG] Teleporting to:", serverId)

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

local function getRequestFunction()
    return request
        or http_request
        or (syn and syn.request)
        or (fluxus and fluxus.request)
end

local function sendDiscordWebhook(isVicious)
    local req = getRequestFunction()
    if not req then
        warn("[WEBHOOK] No request function available")
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

    local success, response = pcall(function()
        return req({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = body
        })
    end)

    if success then
        print("[WEBHOOK] Envoyé :", isVicious)
        return true
    else
        warn("[WEBHOOK] Erreur :", response)
        return false
    end
end

ensureFolder()
loadServerList()

while true do
    local currentJobId = game.JobId

    -- Envoie le webhook une seule fois par serveur
    if lastWebhookJobId ~= currentJobId then
        local isVicious = scanViciousForDuration(CHECK_DURATION, CHECK_INTERVAL)
        print("[DEBUG] Vicious:", isVicious, "| JobId:", currentJobId)

        sendDiscordWebhook(isVicious)
        lastWebhookJobId = currentJobId
    else
        print("[DEBUG] Same server, webhook already sent for JobId:", currentJobId)
    end

    -- Même si Vicious = true, on hop quand même
    local ok = hopServer()

    if not ok then
        warn("[DEBUG] Hop failed, staying on same server. No new webhook will be sent.")
        task.wait(RETRY_DELAY)
    end
end
