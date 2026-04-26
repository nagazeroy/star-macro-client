local Config = {
	CheckInterval = 1,
	TeleportTimeout = 8
}

local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
if not Player then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	Player = Players.LocalPlayer
end

local PlaceId = game.PlaceId

local folderName = "star_macro"
local viciousFile = folderName .. "/vicious.txt"
local commandFile = folderName .. "/hop_control.txt"

local lastLogKey = nil

if not isfolder(folderName) then
	makefolder(folderName)
end

local function ensureLogFile()
	if not isfile(viciousFile) then
		writefile(viciousFile, "Time,Vicious,Position,Server\n")
	end
end

local function ensureCommandFile()
	if not isfile(commandFile) then
		writefile(commandFile, "idle")
	end
end

local function writeCommand(value)
	writefile(commandFile, value)
end

local function readCommand()
	if not isfile(commandFile) then
		return "idle"
	end

	local success, content = pcall(readfile, commandFile)
	if not success or type(content) ~= "string" then
		return "idle"
	end

	content = content:gsub("^%s+", ""):gsub("%s+$", "")
	content = content:gsub("^\239\187\191", "")
	if content == "" then
		return "idle"
	end

	return content
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

local function logViciousState(viciousPath)
	local currentTime = os.date("%Y-%m-%d %H:%M:%S")
	local vicious = viciousPath and "Yes" or "No"
	local position = getObjectPosition(viciousPath)
	local server = game.JobId
	local logKey = table.concat({server, vicious, position}, "|")

	if logKey ~= lastLogKey then
		appendLine(string.format("%s,%s,%s,%s", currentTime, vicious, position, server))
		lastLogKey = logKey
		print("[ OK ] Vicious state written:", viciousFile)
	end

	if viciousPath then
		print("[ OK ] Vicious found!")
		print("[ OK ] Vicious position:", position)
	else
		print("[ OK ] Vicious not found!")
		print("[ OK ] Vicious position: N/A")
	end
end

local function teleportToServer(serverId)
	local oldJobId = game.JobId
	local failed = false

	local connection = TeleportService.TeleportInitFailed:Connect(function(failedPlayer)
		if failedPlayer == Player then
			failed = true
		end
	end)

	local success, result = pcall(function()
		local teleportOptions = Instance.new("TeleportOptions")
		teleportOptions.ServerInstanceId = serverId
		TeleportService:TeleportAsync(PlaceId, { Player }, teleportOptions)
	end)

	if not success then
		connection:Disconnect()
		warn("[ FAIL ] TeleportAsync failed:", tostring(result))
		return false
	end

	local startedAt = os.clock()

	while os.clock() - startedAt < Config.TeleportTimeout do
		if failed then
			connection:Disconnect()
			return false
		end

		if game.JobId ~= oldJobId then
			connection:Disconnect()
			return true
		end

		task.wait(0.25)
	end

	connection:Disconnect()
	return false
end

local function handleCommand()
	local command = readCommand()
	local lowered = string.lower(command)

	if lowered == "idle" then
		return
	end

	local prefix = "target-server:"
	if string.sub(lowered, 1, #prefix) == prefix then
		local serverId = command:sub(#prefix + 1):gsub("^%s+", ""):gsub("%s+$", "")
		writeCommand("idle")

		if serverId == "" then
			return
		end

		print("[ OK ] Targeted server hop requested:", serverId)
		teleportToServer(serverId)
	else
		writeCommand("idle")
		warn("[ FAIL ] Unknown hop command:", command)
	end
end

ensureLogFile()
ensureCommandFile()
print("[ OK ] Monitoring Vicious state...")

while true do
	local viciousPath = getViciousPath()
	logViciousState(viciousPath)
	handleCommand()
	task.wait(Config.CheckInterval)
end
