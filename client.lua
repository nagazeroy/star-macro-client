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

local failedServerIds = {}
local lastLoggedState = nil
local lastLoggedPosition = nil

if not isfolder(folderName) then
    makefolder(folderName)
end

local function ensureLogFile()
    if not isfile(viciousFile) then
        writefile(viciousFile, "Time,Vicious,Position,Server\n")
    end
end

local function appendLine(line)
    if appendfile then
        appendfile(viciousFile, line)
    else
        local previous = ""
        if isfile(viciousFile) then
            previous = readfile(viciousFile)
            if previous ~= "" and string.sub(previous, -1) ~= "\n" then
                previous = previous .. "\n"
            end
        end
        writefile(viciousFile, previous .. line)
    end
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

local function shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = randomObject:NextInteger(1, i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
end

local function getServerCandidates(maxPages, maxCandidates)
    local cursor = nil
    local candidates = {}
    local seen = {}

    for _ = 1, maxPages do
        local servers = listServers(cursor)
        if not servers or type(servers.data) ~= "table" then
            break
        end

        for _, server in ipairs(servers.data) do
            local serverId = tostring(server.id)
            local playing = tonumber(server.playing) or 0
            local maxPlayers = tonumber(server.maxPlayers) or 0

            if serverId ~= JobID and playing < maxPlayers and not failedServerIds[serverId] and not seen[serverId] then
                seen[serverId] = true
                table.insert(candidates, serverId)

                if #candidates >= maxCandidates then
                    break
                end
            end
        end

        if #candidates >= maxCandidates then
            break
        end

        cursor = servers.nextPageCursor

        if not cursor or cursor == "" or cursor == "null" then
            break
        end
    end

    shuffle(candidates)
    return candidates
end

local function teleport(maxPages, maxCandidates)
    local character = Player.Character or Player.CharacterAdded:Wait()
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    local previousAnchored = nil

    if rootPart then
        previousAnchored = rootPart.Anchored
        rootPart.Anchored = true
    end

    local candidates = getServerCandidates(maxPages, maxCandidates)

    if #candidates == 0 then
        if rootPart and rootPart.Parent then
            rootPart.Anchored = previousAnchored
        end
        return false
    end

    for _, targetServerId in ipairs(candidates) do
        local success = pcall(function()
            TeleportService:TeleportToPlaceInstance(PlaceID, targetServerId, Player)
        end)

        if success then
            return true
        end

        failedServerIds[targetServerId] = true
        task.wait(0.2)
    end

    if rootPart and rootPart.Parent then
        rootPart.Anchored = previousAnchored
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

local function writeLogIfNeeded(viciousPath)
    local currentTime = os.date("%Y-%m-%d %H:%M:%S")
    local vicious = viciousPath and "Yes" or "No"
    local position = getObjectPosition(viciousPath)
    local server = game.JobId

    local shouldWrite = false

    if vicious ~= lastLoggedState then
        shouldWrite = true
    elseif vicious == "Yes" and position ~= lastLoggedPosition then
        shouldWrite = true
    end

    if shouldWrite then
        appendLine(string.format("%s,%s,%s,%s\n", currentTime, vicious, position, server))
        lastLoggedState = vicious
        lastLoggedPosition = position
        print("[ OK ] File written:", viciousFile)
    end

    if viciousPath then
        print("[ OK ] Vicious found!")
        print("[ OK ] Vic Position:", position)
    else
        print("[ OK ] Vicious not found!")
        print("[ OK ] Vic Position: N/A")
    end
end

ensureLogFile()

while true do
    local viciousPath = getViciousPath()
    writeLogIfNeeded(viciousPath)

    print("[ OK ] Teleporting to another server...")
    local teleported = teleport(15, 200)

    if not teleported then
        warn("[ ERROR ] No valid server found, retrying server search...")
        task.wait(0.5)
    end
end
