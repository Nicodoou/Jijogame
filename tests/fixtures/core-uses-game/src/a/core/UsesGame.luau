--!strict
local UsesGame = {}

function UsesGame.getPlayers(): any
	return game:GetService("Players")
end

return UsesGame
