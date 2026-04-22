local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local PlaceID = game.PlaceId
local JobID = game.JobId

local WEBHOOK_URL = "https://discord.com/api/webhooks/1496537416356335626/uxX18rqqSu6JcIo4QeXXF-pXijzjq2P-bpEFUOMMeUZfX0m8AxXsVnvjce3rv-goY3tw"
local CHECK_INTERVAL = 5

local lastStatus = nil

local function hasVicious()
    local particles = workspace:FindFirstChild("Particles")
    if not particles then
        return false
    end

    return particles:FindFirstChild("Vicious") ~= nil
end

local function getRequestFunction()
    return request
        or http_request
        or (syn and syn.request)
        or (fluxus and fluxus.request)
end

local function sendDiscordWebhook(isVicious)
    local req = getRequestFunction()

    if not req then
        warn("[WEBHOOK] Aucune fonction request disponible.")
        return false
    end

    local color = isVicious and 65280 or 16711680 -- vert / rouge
    local protocolLink = string.format(
        "roblox://placeID=%s&gameInstanceId=%s",
        tostring(PlaceID),
        tostring(JobID)
    )

    local embed = {
        title = "Vicious Status",
        description = string.format("`Vicious : %s`", tostring(isVicious)),
        color = color,
        fields = {
            {
                name = "Player",
                value = LocalPlayer and LocalPlayer.Name or "Unknown",
                inline = true
            },
            {
                name = "PlaceId",
                value = tostring(PlaceID),
                inline = true
            },
            {
                name = "JobId",
                value = tostring(JobID),
                inline = false
            }
        },
        footer = {
            text = os.date("!%Y-%m-%d %H:%M:%S UTC")
        }
    }

    if isVicious then
        table.insert(embed.fields, {
            name = "Link",
            value = protocolLink,
            inline = false
        })
    end

    local data = {
        embeds = { embed }
    }

    local success, response = pcall(function()
        return req({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode(data)
        })
    end)

    if success then
        print("[WEBHOOK] Envoyé :", isVicious)
        return true
    else
        warn("[WEBHOOK] Erreur :", response)
        return false
    end
end

while true do
    local isVicious = hasVicious()
    print("[DEBUG] Vicious:", isVicious)

    -- envoie au premier check + si le statut change
    if lastStatus == nil or lastStatus ~= isVicious then
        sendDiscordWebhook(isVicious)
        lastStatus = isVicious
    end

    task.wait(CHECK_INTERVAL)
end
