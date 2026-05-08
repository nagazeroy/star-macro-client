print("[ CLIENT ] : Autoexec Script loaded")

local Config = {
	CheckInterval = 1,
	TeleportTimeout = 8
}

local BeeSwarmSimulatorPlaceId = 1537690962

local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

if game.PlaceId ~= BeeSwarmSimulatorPlaceId then
	warn(string.format(
		"[ CLIENT ] star_macro.lua skipped because the current place is %s instead of %s.",
		tostring(game.PlaceId),
		tostring(BeeSwarmSimulatorPlaceId)))
	return
end

local Player = Players.LocalPlayer
if not Player then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	Player = Players.LocalPlayer
end

local function sanitizeFolderName(value)
	return value:gsub('[<>:"/\\|%?%*]', "_")
end

local username = Player.Name
local safeUsername = sanitizeFolderName(username)

local rootFolder = "star_macro"
local accountsFolder = rootFolder .. "/accounts"
local accountFolder = accountsFolder .. "/" .. safeUsername
local viciousFile = accountFolder .. "/vicious.txt"
local targetServerFile = accountFolder .. "/target_server.txt"
local statusFile = accountFolder .. "/status.txt"
local accountFile = accountFolder .. "/account.txt"
local heartbeatFile = accountFolder .. "/heartbeat.txt"
local errorFile = accountFolder .. "/error.txt"

local lastLogKey = nil
local lastHandledTarget = nil

if not isfolder(rootFolder) then
	makefolder(rootFolder)
end

if not isfolder(accountsFolder) then
	makefolder(accountsFolder)
end

if not isfolder(accountFolder) then
	makefolder(accountFolder)
end

local function ensureFile(path, defaultValue)
	if not isfile(path) then
		writefile(path, defaultValue)
	end
end

local function writeStatus(value)
	writefile(statusFile, value)
end

local function writeHeartbeat(state)
	writefile(heartbeatFile, string.format("%s|%s|%s", os.date("%Y-%m-%d %H:%M:%S"), game.JobId, state))
end

local function writeError(message)
	writefile(errorFile, string.format("%s|%s", os.date("%Y-%m-%d %H:%M:%S"), tostring(message)))
end

local function readTrimmedFile(path, defaultValue)
	if not isfile(path) then
		return defaultValue
	end

	local success, content = pcall(readfile, path)
	if not success or type(content) ~= "string" then
		return defaultValue
	end

	content = content:gsub("^\239\187\191", "")
	content = content:gsub("^%s+", ""):gsub("%s+$", "")

	if content == "" then
		return defaultValue
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
	local logKey = table.concat({server, vicious}, "|")

	if logKey ~= lastLogKey then
		appendLine(string.format("%s,%s,%s,%s", currentTime, vicious, position, server))
		lastLogKey = logKey
	end
end

local function consumeTargetServer()
	local serverId = readTrimmedFile(targetServerFile, "")
	if serverId == "" then
		return nil
	end

	if serverId == lastHandledTarget then
		return nil
	end

	writefile(targetServerFile, "")
	lastHandledTarget = serverId
	return serverId
end

local function teleportToServer(serverId)
	local oldJobId = game.JobId
	local failed = false
	local failedReason = "unknown"

	local connection = TeleportService.TeleportInitFailed:Connect(function(failedPlayer, teleportResult, errorMessage)
		if failedPlayer == Player then
			failed = true
			failedReason = tostring(errorMessage or teleportResult or "unknown")
		end
	end)

	local success, result = pcall(function()
		TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, Player)
	end)

	if not success then
		connection:Disconnect()
		failedReason = tostring(result)
		writeStatus("teleport-failed:" .. serverId .. "|" .. failedReason)
		writeError("teleport-failed|" .. serverId .. "|" .. failedReason)
		warn("[ FAIL ] TeleportToPlaceInstance failed:", failedReason)
		return false
	end

	local startedAt = os.clock()

	while os.clock() - startedAt < Config.TeleportTimeout do
		writeHeartbeat("teleporting:" .. serverId)

		if failed then
			connection:Disconnect()
			writeStatus("teleport-failed:" .. serverId .. "|" .. failedReason)
			writeError("teleport-failed|" .. serverId .. "|" .. failedReason)
			return false
		end

		if game.JobId ~= oldJobId then
			connection:Disconnect()
			writefile(errorFile, "")
			writeStatus("teleport-success:" .. serverId)
			return true
		end

		task.wait(0.25)
	end

	connection:Disconnect()
	writeStatus("teleport-timeout:" .. serverId)
	writeError("teleport-timeout|" .. serverId)
	return false
end

local function handleTargetServer()
	local serverId = consumeTargetServer()
	if not serverId then
		return false
	end

	writeStatus("teleporting:" .. serverId)
	teleportToServer(serverId)
	return true
end

ensureFile(viciousFile, "Time,Vicious,Position,Server\n")
writefile(targetServerFile, "")
ensureFile(statusFile, "ready")
writefile(errorFile, "")
writefile(accountFile, username)
writeStatus("ready")
writeHeartbeat("ready")

while true do
	local success, errorMessage = pcall(function()
		local viciousPath = getViciousPath()
		local didTeleport = handleTargetServer()

		if didTeleport then
			return
		end

		logViciousState(viciousPath)
		writefile(errorFile, "")
		writeHeartbeat(viciousPath and "vicious" or "idle")
	end)

	if not success then
		writeStatus("loop-error")
		writeError(errorMessage)
	end

	task.wait(Config.CheckInterval)
end
