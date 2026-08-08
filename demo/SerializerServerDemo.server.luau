local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Serializer = require(ReplicatedStorage.BinarySerializer)

local MAX_PAYLOAD_BYTES = 4096

local DataEvent = Instance.new("RemoteEvent")
DataEvent.Name = "DataEvent"
DataEvent.Parent = ReplicatedStorage

local function sendStateToPlayer(player: Player)
	local state = {
		wave = 7,
		mapName = "Venture",
		enemies = {
			{ id = 1, hp = 100, pos = Vector3.new(10, 0, 20) },
			{ id = 2, hp = 55, pos = Vector3.new(-5, 0, 12) },
			{ id = 3, hp = 200, pos = Vector3.new(0, 3, -8) },
		},
		spawnPoint = CFrame.new(0, 10, 0),
	}

	local buf = Serializer.serialize(state)
	print(`[SERVER] Sending state to {player.Name}: {buffer.len(buf)} bytes`)
	DataEvent:FireClient(player, buf)
end

local function onPlayerAdded(player: Player)
	task.wait(3)
	if not player:IsDescendantOf(Players) then
		return
	end
	sendStateToPlayer(player)
end

DataEvent.OnServerEvent:Connect(function(player, buf)
	if typeof(buf) ~= "buffer" then
		warn(`[SERVER] {player.Name} sent {typeof(buf)} instead of a buffer`)
		return
	end

	if buffer.len(buf) > MAX_PAYLOAD_BYTES then
		warn(`[SERVER] {player.Name} sent {buffer.len(buf)} bytes, limit is {MAX_PAYLOAD_BYTES}`)
		return
	end

	local ok, data = pcall(Serializer.deserialize, buf)
	if not ok then
		warn(`[SERVER] {player.Name} sent data that failed to deserialize: {data}`)
		return
	end

	if type(data) ~= "table" or type(data.action) ~= "string" then
		warn(`[SERVER] {player.Name} sent an unexpected payload shape`)
		return
	end

	print(`[SERVER] {player.Name} -> action "{data.action}" at t={data.timestamp}`)
end)

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
