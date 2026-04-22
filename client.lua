local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local PlaceID = game.PlaceId
local SAVE_FILE = "NotSameServers.json"

local AllIDs = {}
local VisitedIDs = {}
local foundAnything = ""

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

    if success and type(data) == "table" then
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

            if serverId ~= game.JobId and playing < maxPlayers and not hasServerBeenVisited(serverId) then
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

loadServerList()

while true do
    local is_vicious = hasVicious()
    print("[DEBUG] Vicious:", is_vicious)

    if is_vicious then
        print("[DEBUG] Vicious trouvé, stop.")
        break
    end

    local ok = Teleport(10)
    if not ok then
        task.wait(1)
    end

    task.wait(1)
end

ensureFolder()
loadServerList()

while true do
    local is_vicious = hasVicious()
    print("[DEBUG] Vicious:", is_vicious)

    if is_vicious then
        print("[DEBUG] VICIOUS FIND ")
        break
    end

    task.wait(2)
    Teleport()
    task.wait(2)
end
