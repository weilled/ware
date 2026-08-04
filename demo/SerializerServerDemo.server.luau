local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Serializer = require(ReplicatedStorage.BinarySerializer)
local DataEvent = ReplicatedStorage.DataEvent

local function sendStateToPlayer(player: Player)
	local state = {
		wave = 7,
		mapName = "Venture",
		enemies = {
			{ id = 1, hp = 100, pos = Vector3.new(10, 0, 20) },
			{ id = 2, hp = 55,  pos = Vector3.new(-5, 0, 12) },
			{ id = 3, hp = 200, pos = Vector3.new(0, 3, -8) },
		},
		spawnPoint = CFrame.new(0, 10, 0),
	}
	local buf = Serializer.serialize(state)
	print(`[SERVER] Sending state to player {player.Name}: {buffer.len(buf)} bytes`)
	DataEvent:FireClient(player, buf)
end

DataEvent.OnServerEvent:Connect(function(player, buf)
	-- Never trust the client: validate the type and wrap in pcall
	if typeof(buf) ~= "buffer" then
		warn(`[SERVER] {player.Name} sent a non-buffer value`)
		return
	end

	local ok, data = pcall(Serializer.deserialize, buf)
	if not ok then
		warn(`[SERVER] Corrupt data received from {player.Name}`)
		return
	end

	if typeof(data) == "table" and typeof(data.action) == "string" then
		print(`[SERVER] {player.Name} -> action: {data.action} (t={data.timestamp})`)
	end
end)

Players.PlayerAdded:Connect(function(player)
	task.wait(3)
	sendStateToPlayer(player)
end)
