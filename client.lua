
local Players = game:GetService("Players")
local PlaceID = game.PlaceId
local LocalPlayer = Players.LocalPlayer
local folderName = "star_macro"
local viciousFile = folderName .. "/vicious.txt"

if not isfolder(folderName) then
    makefolder(folderName)
end

local Player = game.Players.LocalPlayer    
local Http = game:GetService("HttpService")
local TPS = game:GetService("TeleportService")
local Api = "https://games.roblox.com/v1/games/"

local _place,_id = game.PlaceId, game.JobId
-- Asc for lowest player count, Desc for highest player count
local _servers = Api.._place.."/servers/Public?sortOrder=Asc&limit=10"
function ListServers(cursor)
   local Raw = game:HttpGet(_servers .. ((cursor and "&cursor="..cursor) or ""))
   return Http:JSONDecode(Raw)
end

local function teleport()
   Player.Character.HumanoidRootPart.Anchored = true
   local Servers = ListServers()
   local Server = Servers.data[math.random(1,#Servers.data)]
   TPS:TeleportToPlaceInstance(_place, Server.id, Player)
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

    if viciousPath then
        break
    end

    task.wait(1)
    print("[ OK ] Teleporting to another server...")
    teleport()
end
