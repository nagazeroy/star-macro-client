local Config = {
	MaxStore = 3600,
	CheckInterval = 2500,
	TeleportInterval = 1000,
	TeleportTimeout = 8,
	MaxCandidates = 200
}

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
if not Player then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	Player = Players.LocalPlayer
end

local PlaceId = game.PlaceId
local JobId = game.JobId

local folderName = "star_macro"
local viciousFile = folderName .. "/vicious.txt"

local rootFolder = "ServerHop"
local storageFile = rootFolder .. "/" .. tostring(PlaceId) .. ".json"

local lastLogKey = nil
local randomObject = Random.new()

if not isfolder(folderName) then
	makefolder(folderName)
end

if not isfolder(rootFolder) then
	makefolder(rootFolder)
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

local function logViciousState(viciousPath)
	local currentTime = os.date("%Y-%m-%d %H:%M:%S")
	local vicious = viciousPath and "Yes" or "No"
	local position = getObjectPosition(viciousPath)
	local server = game.JobId
	local logKey = table.concat({server, vicious, position}, "|")

	if logKey ~= lastLogKey then
		appendLine(string.format("%s,%s,%s,%s", currentTime, vicious, position, server))
		lastLogKey = logKey
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

local function loadHopData()
	local data = {
		Start = tick(),
		Jobs = {}
	}

	if isfile(storageFile) then
		local success, decoded = pcall(function()
			return HttpService:JSONDecode(readfile(storageFile))
		end)

		if success and type(decoded) == "table" and type(decoded.Jobs) == "table" and decoded.Start then
			if tick() - decoded.Start < Config.MaxStore then
				data = decoded
			end
		end
	end

	if not table.find(data.Jobs, JobId) then
		table.insert(data.Jobs, JobId)
	end

	writefile(storageFile, HttpService:JSONEncode(data))
	return data
end

local function saveHopData(data)
	writefile(storageFile, HttpService:JSONEncode(data))
end

local function addVisitedJob(data, serverId)
	if not table.find(data.Jobs, serverId) then
		table.insert(data.Jobs, serverId)
		saveHopData(data)
	end
end

local function sendRequest(url)
	local httpRequest = request or http_request or (syn and syn.request) or (fluxus and fluxus.request)

	if httpRequest then
		local success, response = pcall(httpRequest, {
			Url = url,
			Method = "GET"
		})

		if success and response and response.Body then
			return response.Body
		end
	end

	local success, body = pcall(function()
		return game:HttpGet(url)
	end)

	if success then
		return body
	end

	return nil
end

local function decodeBody(body)
	if not body then
		return nil
	end

	local success, decoded = pcall(function()
		return HttpService:JSONDecode(body)
	end)

	if success and type(decoded) == "table" then
		return decoded
	end

	return nil
end

local function shuffle(list)
	for index = #list, 2, -1 do
		local randomIndex = randomObject:NextInteger(1, index)
		list[index], list[randomIndex] = list[randomIndex], list[index]
	end
end

local function collectServers(data)
	local servers = {}
	local seen = {}
	local cursor = ""

	repeat
		local url = "https://games.roblox.com/v1/games/" .. tostring(PlaceId) .. "/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true"
		if cursor ~= "" then
			url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
		end

		local body = sendRequest(url)
		local decoded = decodeBody(body)

		if decoded and type(decoded.data) == "table" then
			for _, server in ipairs(decoded.data) do
				if type(server) == "table" and server.id and tonumber(server.playing) and tonumber(server.maxPlayers) then
					local serverId = tostring(server.id)
					local playing = tonumber(server.playing) or 0
					local maxPlayers = tonumber(server.maxPlayers) or 0

					if serverId ~= JobId and playing < maxPlayers and not table.find(data.Jobs, serverId) and not seen[serverId] then
						seen[serverId] = true
						table.insert(servers, serverId)

						if #servers >= Config.MaxCandidates then
							break
						end
					end
				end
			end

			if #servers >= Config.MaxCandidates then
				break
			end

			if decoded.nextPageCursor and decoded.nextPageCursor ~= "" and decoded.nextPageCursor ~= "null" then
				cursor = decoded.nextPageCursor
			else
				cursor = nil
			end
		else
			cursor = nil
		end
	until not cursor

	shuffle(servers)
	return servers
end

local function attemptTeleport(serverId, data)
	local failed = false
	local oldJobId = game.JobId

	local connection = TeleportService.TeleportInitFailed:Connect(function(failedPlayer)
		if failedPlayer == Player then
			failed = true
		end
	end)

	local success = pcall(function()
		TeleportService:TeleportToPlaceInstance(PlaceId, serverId, Player)
	end)

	if not success then
		connection:Disconnect()
		addVisitedJob(data, serverId)
		return false
	end

	local startTime = os.clock()

	while os.clock() - startTime < Config.TeleportTimeout do
		if failed then
			connection:Disconnect()
			addVisitedJob(data, serverId)
			return false
		end

		if game.JobId ~= oldJobId then
			connection:Disconnect()
			return true
		end

		task.wait(0.25)
	end

	connection:Disconnect()
	addVisitedJob(data, serverId)
	return false
end

getgenv().ServerHop = function()
	local data = loadHopData()

	while true do
		local servers = collectServers(data)

		if #servers == 0 then
			task.wait(Config.CheckInterval / 1000)
			data = loadHopData()
			continue
		end

		while #servers > 0 do
			local serverId = table.remove(servers, 1)
			print("[ OK ] Trying server:", serverId)

			local success = attemptTeleport(serverId, data)
			if success then
				return true
			end

			task.wait(Config.TeleportInterval / 1000)
		end

		task.wait(Config.CheckInterval / 1000)
		data = loadHopData()
	end
end

ensureLogFile()

while true do
	local viciousPath = getViciousPath()
	logViciousState(viciousPath)
	print("[ OK ] Teleporting to another server...")
	getgenv().ServerHop()
	task.wait(2)
end
