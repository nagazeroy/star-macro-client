print("[ STAR MCRO ] Loaded Scipt !")
local Config = {
	CheckInterval = 1,
	TeleportTimeout = 8
}

local BeeSwarmSimulatorPlaceId = 1537690962

local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

if game.PlaceId ~= BeeSwarmSimulatorPlaceId then
	warn(string.format(
		"[ INFO ] star_macro.lua skipped because the current place is %s instead of %s.",
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
local windyFile = accountFolder .. "/windy.txt"
local targetServerFile = accountFolder .. "/target_server.txt"
local statusFile = accountFolder .. "/status.txt"
local accountFile = accountFolder .. "/account.txt"
local heartbeatFile = accountFolder .. "/heartbeat.txt"
local errorFile = accountFolder .. "/error.txt"
local trackedNpcFile = rootFolder .. "/tracked_npcs.txt"

local lastLogKeys = {}
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

local function appendLine(path, line)
	if appendfile then
		appendfile(path, line .. "\n")
	else
		local previous = ""
		if isfile(path) then
			previous = readfile(path)
			if previous ~= "" and string.sub(previous, -1) ~= "\n" then
				previous = previous .. "\n"
			end
		end
		writefile(path, previous .. line .. "\n")
	end
end

local function getViciousPath()
	local particles = workspace:FindFirstChild("Particles")
	if not particles then
		return nil
	end

	return particles:FindFirstChild("Vicious")
end

local function getWindyPath()
	local npcBees = workspace:FindFirstChild("NPCBees")
	if not npcBees then
		return nil
	end

	return npcBees:FindFirstChild("Windy")
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

local function getTrackedNpcs()
	local tracked = {
		vicious = false,
		windy = false
	}

	local value = readTrimmedFile(trackedNpcFile, "vicious,windy")
	for token in string.gmatch(string.lower(value), "[^,%s]+") do
		if token == "vicious" or token == "windy" then
			tracked[token] = true
		end
	end

	if not tracked.vicious and not tracked.windy then
		tracked.vicious = true
		tracked.windy = true
	end

	return tracked
end

local function logNpcState(kind, path, instance)
	local currentTime = os.date("%Y-%m-%d %H:%M:%S")
	local state = instance and "Yes" or "No"
	local position = getObjectPosition(instance)
	local server = game.JobId
	local logKey = table.concat({kind, server, state}, "|")

	if logKey ~= lastLogKeys[kind] then
		appendLine(path, string.format("%s,%s,%s,%s", currentTime, state, position, server))
		lastLogKeys[kind] = logKey
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

ensureFile(viciousFile, "Time,State,Position,Server\n")
ensureFile(windyFile, "Time,State,Position,Server\n")
ensureFile(trackedNpcFile, "vicious,windy")
writefile(targetServerFile, "")
ensureFile(statusFile, "ready")
writefile(errorFile, "")
writefile(accountFile, username)
writeStatus("ready")
writeHeartbeat("ready")

while true do
	local success, errorMessage = pcall(function()
		local trackedNpcs = getTrackedNpcs()
		local viciousPath = getViciousPath()
		local windyPath = getWindyPath()
		local didTeleport = handleTargetServer()

		if didTeleport then
			return
		end

		if trackedNpcs.vicious then
			logNpcState("vicious", viciousFile, viciousPath)
		end

		if trackedNpcs.windy then
			logNpcState("windy", windyFile, windyPath)
		end

		writefile(errorFile, "")

		local heartbeatStates = {}
		if trackedNpcs.vicious and viciousPath then
			table.insert(heartbeatStates, "vicious")
		end
		if trackedNpcs.windy and windyPath then
			table.insert(heartbeatStates, "windy")
		end
		if #heartbeatStates == 0 then
			table.insert(heartbeatStates, "idle")
		end

		writeHeartbeat(table.concat(heartbeatStates, "+"))
	end)

	if not success then
		writeStatus("loop-error")
		writeError(errorMessage)
	end

	task.wait(Config.CheckInterval)
end
