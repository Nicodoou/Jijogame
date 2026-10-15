--!strict
local Players = game:GetService("Players")

local Spawner = {}

function Spawner.countPlayers(): number
	local part = Instance.new("Part")
	part.Position = Vector3.new(0, 1, 0)
	task.wait()
	return #Players:GetPlayers()
end

return Spawner
