local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local PlaceID = game.PlaceId

local SAVE_FILE = "NotSameServers.json"
local FOLDER_NAME = "star_macro"

local AllIDs = {}
local foundAnything = ""

-- ========= Utils =========

local function getCurrentHour()
    return os.date("!*t").hour
end

local function ensureFolder()
    if not isfolder(FOLDER_NAME) then
        makefolder(FOLDER_NAME)
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
end

local function resetServerListIfHourChanged()
    local currentHour = getCurrentHour()

    if tonumber(AllIDs[1]) ~= currentHour then
        pcall(function()
            delfile(SAVE_FILE)
        end)

        AllIDs = { currentHour }
        saveServerList()
    end
end

local function hasServerBeenVisited(serverId)
    for i = 2, #AllIDs do
        if tostring(AllIDs[i]) == tostring(serverId) then
            return true
        end
    end
    return false
end

local function getServerPage(cursor)
    local url = "https://games.roblox.com/v1/games/" .. PlaceID .. "/servers/Public?sortOrder=Asc&limit=100"

    if cursor and cursor ~= "" then
        url = url .. "&cursor=" .. cursor
    end

    local success, result = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)

    if success then
        return result
    end

    return nil
end

local function hasVicious()
    local particles = workspace:FindFirstChild("Particles")
    if not particles then
        return false
    end

    return particles:FindFirstChild("Vicious") ~= nil
end

-- ========= Teleport =========

local function TPReturner()
    resetServerListIfHourChanged()

    local site = getServerPage(foundAnything)
    if not site or not site.data then
        warn("[DEBUG] Failed to found Server")
        return false
    end

    if site.nextPageCursor and site.nextPageCursor ~= "null" then
        foundAnything = site.nextPageCursor
    else
        foundAnything = ""
    end

    for _, server in pairs(site.data) do
        local serverId = tostring(server.id)
        local maxPlayers = tonumber(server.maxPlayers) or 0
        local playing = tonumber(server.playing) or 0

        if playing < maxPlayers and not hasServerBeenVisited(serverId) then
            table.insert(AllIDs, serverId)
            saveServerList()

            local success, err = pcall(function()
                TeleportService:TeleportToPlaceInstance(PlaceID, serverId, LocalPlayer)
            end)

            if not success then
                warn("[DEBUG] Teleport Error :", err)
                return false
            end

            return true
        end
    end

    return false
end

local function Teleport()
    local teleported = TPReturner()

    if not teleported and foundAnything ~= "" then
        teleported = TPReturner()
    end

    return teleported
end

-- ========= Main =========

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
