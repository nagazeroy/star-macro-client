local Config = {
	CheckInterval = 1
}

local Players = game:GetService("Players")

local Player = Players.LocalPlayer
if not Player then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	Player = Players.LocalPlayer
end

local folderName = "star_macro"
local viciousFile = folderName .. "/vicious.txt"

local lastLogKey = nil

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

local function logViciousState(viciousPath)
	local currentTime = os.date("%Y-%m-%d %H:%M:%S")
	local vicious = viciousPath and "Yes" or "No"
	local position = getObjectPosition(viciousPath)
	local server = game.JobId
	local logKey = table.concat({server, vicious}, "|")

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

ensureLogFile()
print("[ OK ] Monitoring Vicious state...")

while true do
	local viciousPath = getViciousPath()
	logViciousState(viciousPath)
	task.wait(Config.CheckInterval)
end
