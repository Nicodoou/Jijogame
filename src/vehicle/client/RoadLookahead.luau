--!strict
-- Adaptador del límite de dirección según la curva: le pide al mundo el camino cerca del auto y adelante, y descarta
-- los puntos que saltan de tramo (U cerradas). Devuelve el camino como datos para el núcleo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoadPoint = require(ReplicatedStorage.shared.contracts.RoadPoint)
local RoadSteerLimit = require(ReplicatedStorage.vehicle.core.RoadSteerLimit)
local VehicleTypes = require(ReplicatedStorage.vehicle.core.VehicleTypes)

type ChassisSample = VehicleTypes.ChassisSample
type VehicleSettings = VehicleTypes.VehicleSettings

local RoadLookahead = {}
RoadLookahead.__index = RoadLookahead

export type RoadLookahead = typeof(setmetatable(
	{} :: {
		_getNearestRoadPoint: RoadPoint.GetNearestRoadPoint,
		_lastArc: number?,
		_rejectedCount: number,
	},
	RoadLookahead
))

function RoadLookahead.new(getNearestRoadPoint: RoadPoint.GetNearestRoadPoint): RoadLookahead
	return setmetatable(
		{ _getNearestRoadPoint = getNearestRoadPoint, _lastArc = nil, _rejectedCount = 0 },
		RoadLookahead
	)
end

-- Nil si el límite está apagado, no hay camino cerca o el punto cercano saltó de tramo.
function RoadLookahead.sample(
	self: RoadLookahead,
	chassis: ChassisSample,
	config: VehicleSettings
): RoadSteerLimit.RoadAhead?
	if not config.ROAD_STEER_LIMIT_ENABLED then
		return nil
	end
	local near = self._getNearestRoadPoint(chassis.position)
	if near == nil then
		return nil
	end
	local isAccepted
	isAccepted, self._lastArc, self._rejectedCount =
		RoadSteerLimit.track(self._lastArc, self._rejectedCount, near.arcLength, config)
	local ahead = if isAccepted
		then self._getNearestRoadPoint(chassis.position + chassis.forward * config.ROAD_STEER_LOOKAHEAD)
		else nil
	if ahead == nil then
		return nil
	end
	return { near = near, ahead = ahead }
end

return RoadLookahead
