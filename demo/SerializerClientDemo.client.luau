local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Serializer = require(ReplicatedStorage.BinarySerializer)
local DataEvent = ReplicatedStorage:WaitForChild("DataEvent")

DataEvent.OnClientEvent:Connect(function(buf)
	if typeof(buf) ~= "buffer" then
		return
	end

	local ok, state = pcall(Serializer.deserialize, buf)
	if not ok then
		warn(`[CLIENT] Failed to deserialize state: {state}`)
		return
	end

	if type(state) ~= "table" or type(state.enemies) ~= "table" then
		warn("[CLIENT] Unexpected state shape")
		return
	end

	print(`[CLIENT] Wave {state.wave}, map "{state.mapName}", {#state.enemies} enemies`)
	for _, enemy in state.enemies do
		print(`[CLIENT]   Enemy #{enemy.id}: hp={enemy.hp}, pos={enemy.pos}`)
	end
end)

task.wait(5)

local buf = Serializer.serialize({
	action = "jump",
	timestamp = workspace:GetServerTimeNow(),
})
print(`[CLIENT] Sending action to server: {buffer.len(buf)} bytes`)
DataEvent:FireServer(buf)
