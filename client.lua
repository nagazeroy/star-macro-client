local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local PlaceID = game.PlaceId
local LocalPlayer = Players.LocalPlayer

local allIDs = {}
local foundAnything = ""

local folderName = "star_macro"
local viciousFile = folderName .. "/vicious.txt"
local serverFile = "NotSameServers.json"

if not isfolder(folderName) then
    makefolder(folderName)
end

local function getCurrentHour()
    return os.date("!*t").hour
end

local function loadVisitedServers()
    local success, data = pcall(function()
        return HttpService:JSONDecode(readfile(serverFile))
    end)

    if success and type(data) == "table" then
        allIDs = data
    else
        allIDs = { getCurrentHour() }
        writefile(serverFile, HttpService:JSONEncode(allIDs))
    end
end

local function saveVisitedServers()
    writefile(serverFile, HttpService:JSONEncode(allIDs))
end

local function resetVisitedServersIfNeeded()
    local currentHour = getCurrentHour()

    if tonumber(allIDs[1]) ~= currentHour then
        pcall(function()
            delfile(serverFile)
        end)

        allIDs = { currentHour }
        saveVisitedServers()
    end
end

local function hasVisitedServer(serverId)
    for index = 2, #allIDs do
        if tostring(allIDs[index]) == tostring(serverId) then
            return true
        end
    end

    return false
end

local function getServerPage()
    local url = "https://games.roblox.com/v1/games/" .. PlaceID .. "/servers/Public?sortOrder=Asc&limit=100"

    if foundAnything ~= "" then
        url = url .. "&cursor=" .. foundAnything
    end

    local success, result = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)

    if not success or type(result) ~= "table" then
        return nil
    end

    return result
end

local function tpReturner()
    resetVisitedServersIfNeeded()

    local site = getServerPage()
    if not site or type(site.data) ~= "table" then
        return false
    end

    if site.nextPageCursor and site.nextPageCursor ~= "null" then
        foundAnything = site.nextPageCursor
    else
        foundAnything = ""
    end

    for _, serverData in pairs(site.data) do
        local serverId = tostring(serverData.id)
        local maxPlayers = tonumber(serverData.maxPlayers) or 0
        local playing = tonumber(serverData.playing) or 0

        if playing < maxPlayers and not hasVisitedServer(serverId) then
            table.insert(allIDs, serverId)
            saveVisitedServers()

            local success = pcall(function()
                TeleportService:TeleportToPlaceInstance(PlaceID, serverId, LocalPlayer)
            end)

            if success then
                return true
            end
        end
    end

    return false
end

local function teleport()
    if tpReturner() then
        return true
    end

    if foundAnything ~= "" then
        return tpReturner()
    end

    return false
end

local function getViciousPath()
    local particles = workspace:FindFirstChild("Particles")
    if not particles then
        return nil
    end

    return particles:FindFirstChild("Vicious")
end

local function getObjectPosition(instance)
    if not instance then
        return "N/A"
    end

    if instance:IsA("BasePart") then
        return tostring(instance.Position)
    end

    if instance:IsA("Model") then
        return tostring(instance:GetPivot().Position)
    end

    local success, position = pcall(function()
        return instance.Position
    end)

    if success and position then
        return tostring(position)
    end

    return "N/A"
end

loadVisitedServers()

local lines = {}
table.insert(lines, "Time,Vicious,Position,Server")

while true do
    local viciousPath = getViciousPath()

    local currentTime = os.date("%Y-%m-%d %H:%M:%S")
    local vicious = viciousPath and "Yes" or "No"
    local position = getObjectPosition(viciousPath)
    local server = game.JobId

    if viciousPath then
        print("[ OK ] Vicious found!")
        print("[ OK ] Vic Position:", position)
    else
        print("[ OK ] Vicious not found!")
        print("[ OK ] Vic Position: N/A")
    end

    table.insert(lines, string.format("%s,%s,%s,%s", currentTime, vicious, position, server))
    writefile(viciousFile, table.concat(lines, "\n"))
    print("[ OK ] File written:", viciousFile)

    task.wait(1)
    print("[ OK ] Teleporting to another server...")
    teleport()
    task.wait(3)
end
