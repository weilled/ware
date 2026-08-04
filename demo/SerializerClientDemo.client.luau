-- Client receives state from the server and sends an action.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Serializer = require(ReplicatedStorage.BinarySerializer)
local DataEvent = ReplicatedStorage:WaitForChild("DataEvent")

DataEvent.OnClientEvent:Connect(function(buf: buffer)
	local state = Serializer.deserialize(buf)
	print(`[CLIENT] Received state: wave {state.wave}, map "{state.mapName}", enemies: {#state.enemies}`)
	for _, enemy in state.enemies do
		print(`[CLIENT]   Enemy #{enemy.id}: HP={enemy.hp}, position={enemy.pos}`)
	end
end)

task.wait(5)
local buf = Serializer.serialize({
	action = "jump",
	timestamp = workspace:GetServerTimeNow(),
})
print(`[CLIENT] Sending action to server: {buffer.len(buf)} bytes`)
DataEvent:FireServer(buf)
