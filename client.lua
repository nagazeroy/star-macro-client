local Config = {
	CheckInterval = 1,
	ServerObservationSeconds = 6,
	TeleportTimeout = 8,
	TeleportRetryDelay = 2
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
local serverQueueFile = folderName .. "/server_queue.txt"
local hopStatusFile = folderName .. "/hop_status.txt"

local lastLogKey = nil
local serverEnteredAt = os.clock()
local hopAttemptedForThisServer = false

if not isfolder(folderName) then
	makefolder(folderName)
end

local function ensureFile(path, defaultValue)
	if not isfile(path) then
		writefile(path, defaultValue)
	end
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

local function writeStatus(value)
	writefile(hopStatusFile, value)
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

local function loadServerQueue()
	local content = readTrimmedFile(serverQueueFile, "")
	if content == "" then
		return {}
	end

	local queue = {}

	for line in string.gmatch(content, "[^\r\n]+") do
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" then
			table.insert(queue, line)
		end
	end

	return queue
end

local function saveServerQueue(queue)
	if #queue == 0 then
		writefile(serverQueueFile, "")
		return
	end

	writefile(serverQueueFile, table.concat(queue, "\n") .. "\n")
end

local function popNextServerId()
	local queue = loadServerQueue()

	if #queue == 0 then
		return nil
	end

	local serverId = table.remove(queue, 1)
	saveServerQueue(queue)
	return serverId
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
		writeStatus("teleport-failed:" .. serverId)
		return false
	end

	local startedAt = os.clock()

	while os.clock() - startedAt < Config.TeleportTimeout do
		if failed then
			connection:Disconnect()
			writeStatus("teleport-failed:" .. serverId)
			return false
		end

		if game.JobId ~= oldJobId then
			connection:Disconnect()
			writeStatus("teleport-success:" .. serverId)
			return true
		end

		task.wait(0.25)
	end

	connection:Disconnect()
	writeStatus("teleport-timeout:" .. serverId)
	return false
end

local function maybeHop(viciousPath)
	if viciousPath then
		writeStatus("vicious-found")
		return
	end

	if hopAttemptedForThisServer then
		return
	end

	if os.clock() - serverEnteredAt < Config.ServerObservationSeconds then
		return
	end

	local serverId = popNextServerId()
	if not serverId then
		writeStatus("queue-empty")
		return
	end

	hopAttemptedForThisServer = true
	print("[ OK ] Targeted queued hop:", serverId)
	writeStatus("teleporting:" .. serverId)

	local success = teleportToServer(serverId)
	if not success then
		task.wait(Config.TeleportRetryDelay)
		hopAttemptedForThisServer = false
	end
end

ensureFile(viciousFile, "Time,Vicious,Position,Server\n")
ensureFile(serverQueueFile, "")
ensureFile(hopStatusFile, "ready")
writeStatus("ready")
print("[ OK ] Monitoring Vicious state...")

while true do
	local viciousPath = getViciousPath()
	logViciousState(viciousPath)
	maybeHop(viciousPath)
	task.wait(Config.CheckInterval)
end
