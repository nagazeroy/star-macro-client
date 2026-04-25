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
local lastLoggedKey = nil

failedServerIds[JobID] = true

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
        appendfile(viciousFile, line .. "\n")
    else
        local previous = ""
        if isfile(viciousFile) then
            previous = readfile(viciousFile)
            if previous ~= "" and string.sub(previous, -1) ~= "\n" then
                previous = previous .. "\n"
            end
        end
        writefile(viciousFile, previous .. line .. "\n")
    end
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

local function buildLogEntry(viciousPath)
    local currentTime = os.date("%Y-%m-%d %H:%M:%S")
    local vicious = viciousPath and "Yes" or "No"
    local position = getObjectPosition(viciousPath)
    local server = game.JobId
    local key = table.concat({server, vicious, position}, "|")
    local line = string.format("%s,%s,%s,%s", currentTime, vicious, position, server)

    return key, line, vicious, position
end

local function writeLogEntry(viciousPath)
    local key, line, vicious, position = buildLogEntry(viciousPath)

    if key ~= lastLoggedKey then
        appendLine(line)
        lastLoggedKey = key
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

local function requestServerPage(cursor)
    local url = api .. PlaceID .. "/servers/Public?sortOrder=Asc&limit=100"

    if cursor and cursor ~= "" then
        url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
    end

    local success, result = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)

    if not success or type(result) ~= "table" or type(result.data) ~= "table" then
        return nil
    end

    return result
end

local function shuffle(list)
    for index = #list, 2, -1 do
        local randomIndex = randomObject:NextInteger(1, index)
        list[index], list[randomIndex] = list[randomIndex], list[index]
    end
end

local function collectServerCandidates(maxPages, maxCandidates)
    local cursor = nil
    local candidates = {}
    local seen = {}

    for _ = 1, maxPages do
        local page = requestServerPage(cursor)
        if not page then
            break
        end

        for _, serverData in ipairs(page.data) do
            local serverId = tostring(serverData.id)
            local playing = tonumber(serverData.playing) or 0
            local maxPlayers = tonumber(serverData.maxPlayers) or 0

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

        cursor = page.nextPageCursor

        if not cursor or cursor == "" or cursor == "null" then
            break
        end
    end

    shuffle(candidates)

    return candidates
end

local function waitForCharacter()
    local character = Player.Character or Player.CharacterAdded:Wait()
    local rootPart = character:FindFirstChild("HumanoidRootPart")

    if not rootPart then
        rootPart = character:WaitForChild("HumanoidRootPart", 5)
    end

    return character, rootPart
end

local function tryTeleportToServer(serverId, timeoutSeconds)
    local _, rootPart = waitForCharacter()
    local previousAnchored = nil
    local failed = false

    local connection = TeleportService.TeleportInitFailed:Connect(function(failedPlayer)
        if failedPlayer == Player then
            failed = true
        end
    end)

    if rootPart then
        previousAnchored = rootPart.Anchored
        rootPart.Anchored = true
    end

    local success = pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceID, serverId, Player)
    end)

    if not success then
        connection:Disconnect()

        if rootPart and rootPart.Parent then
            rootPart.Anchored = previousAnchored
        end

        failedServerIds[serverId] = true
        return false
    end

    local startTime = os.clock()

    while os.clock() - startTime < timeoutSeconds do
        if failed then
            connection:Disconnect()

            if rootPart and rootPart.Parent then
                rootPart.Anchored = previousAnchored
            end

            failedServerIds[serverId] = true
            return false
        end

        task.wait(0.2)
    end

    connection:Disconnect()

    if rootPart and rootPart.Parent then
        rootPart.Anchored = previousAnchored
    end

    failedServerIds[serverId] = true
    return false
end

local function hopServers(maxPages, maxCandidates, timeoutSeconds)
    local candidates = collectServerCandidates(maxPages, maxCandidates)

    if #candidates == 0 then
        return false
    end

    for _, serverId in ipairs(candidates) do
        print("[ OK ] Trying server:", serverId)
        local success = tryTeleportToServer(serverId, timeoutSeconds)

        if success then
            return true
        end
    end

    return false
end

local function main()
    ensureLogFile()

    while true do
        local viciousPath = getViciousPath()
        writeLogEntry(viciousPath)

        if viciousPath then
            print("[ OK ] Script stopped.")
            return
        end
        wait(3)
        print("[ OK ] Teleporting to another server...")

        local success = hopServers(20, 300, 8)

        if not success then
            warn("[ ERROR ] No valid server found, retrying soon...")
            task.wait(5)
        end
    end
end

main()
