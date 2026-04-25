local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local Player = Players.LocalPlayer
local PlaceID = game.PlaceId
local JobID = game.JobId
local folderName = "star_macro"
local viciousFile = folderName .. "/vicious.txt"
local api = "https://games.roblox.com/v1/games/"
local randomObject = Random.new()

if not isfolder(folderName) then
    makefolder(folderName)
end

local function listServers(cursor)
    local url = api .. PlaceID .. "/servers/Public?sortOrder=Asc&limit=100"

    if cursor and cursor ~= "" then
        url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
    end

    local success, result = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)

    if not success or type(result) ~= "table" then
        return nil
    end

    return result
end

local function getTeleportTarget(maxPages)
    local cursor = nil
    local pageCount = 0
    local candidates = {}

    while pageCount < maxPages do
        local servers = listServers(cursor)
        if not servers or type(servers.data) ~= "table" then
            break
        end

        for _, server in ipairs(servers.data) do
            local serverId = tostring(server.id)
            local playing = tonumber(server.playing) or 0
            local maxPlayers = tonumber(server.maxPlayers) or 0

            if serverId ~= JobID and playing < maxPlayers then
                table.insert(candidates, serverId)
            end
        end

        cursor = servers.nextPageCursor
        pageCount = pageCount + 1

        if not cursor or cursor == "" or cursor == "null" then
            break
        end
    end

    if #candidates == 0 then
        return nil
    end

    return candidates[randomObject:NextInteger(1, #candidates)]
end

local function teleport()
    local character = Player.Character or Player.CharacterAdded:Wait()
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    local targetServerId = getTeleportTarget(5)

    if not targetServerId then
        warn("[ ERROR ] No valid server found")
        return false
    end

    local wasAnchored = false

    if rootPart then
        wasAnchored = rootPart.Anchored
        rootPart.Anchored = true
    end

    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceID, targetServerId, Player)
    end)

    if not success then
        if rootPart and rootPart.Parent then
            rootPart.Anchored = wasAnchored
        end

        warn("[ ERROR ] Teleport failed:", err)
        return false
    end

    return true
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

    if viciousPath then
        break
    end

    task.wait(1)
    print("[ OK ] Teleporting to another server...")
    teleport()
end
