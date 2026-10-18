--!strict
-- Lee los golpes del auto (WP-18): se suscribe con `BindToCollisionSummaries` a cada caja de colisión y convierte cada
-- resumen en (pieza, velocidad de impacto). Solo funciona en el cliente dueño de red del auto. Qué golpes cuentan lo
-- decide `HitFilter` del núcleo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DamageTypes = require(ReplicatedStorage.vehicle.core.damage.DamageTypes)
local HitFilter = require(ReplicatedStorage.vehicle.core.damage.HitFilter)
local VehicleParts = require(ReplicatedStorage.vehicle.shared.VehicleParts)

type PieceSpecs = DamageTypes.PieceSpecs

export type HitHandler = (pieceId: string, impactSpeed: number) -> ()

-- Lo que usamos de cada resumen de colisión del motor.
type Summary = {
	Part0: BasePart,
	Part1: BasePart,
	Normal: Vector3,
	RelativeVelocity: Vector3,
}

local CollisionReader = {}
CollisionReader.__index = CollisionReader

export type CollisionReader = typeof(setmetatable(
	{} :: {
		_specs: PieceSpecs,
		_onHit: HitHandler,
		_clock: () -> number,
		_connections: { RBXScriptConnection },
	},
	CollisionReader
))

function CollisionReader.new(specs: PieceSpecs, onHit: HitHandler, clock: () -> number): CollisionReader
	return setmetatable({ _specs = specs, _onHit = onHit, _clock = clock, _connections = {} }, CollisionReader)
end

-- La velocidad normal relativa: el signo depende del orden de las partes, así que se usa el valor absoluto (exp/hitbox).
local function normalSpeed(summary: Summary): number
	return math.abs(summary.RelativeVelocity:Dot(summary.Normal))
end

local function readSummaries(
	self: CollisionReader,
	part: BasePart,
	pieceId: string,
	cooldowns: HitFilter.Cooldowns,
	summaries: { Summary }
)
	for _, summary in summaries do
		local other = if summary.Part0 == part then summary.Part1 else summary.Part0
		local speed = normalSpeed(summary)
		local counts = HitFilter.shouldCount(self._specs[pieceId], speed, summary.Normal.Y, other:IsA("Terrain"))
		if counts and HitFilter.registerHit(cooldowns, other, self._clock()) then
			self._onHit(pieceId, speed)
		end
	end
end

local function bindPart(self: CollisionReader, instance: Instance)
	local pieceId = instance:GetAttribute(VehicleParts.HITBOX_PIECE_ATTRIBUTE)
	if not instance:IsA("BasePart") or type(pieceId) ~= "string" or self._specs[pieceId] == nil then
		return
	end
	local cooldowns = HitFilter.newCooldowns()
	table.insert(
		self._connections,
		instance:BindToCollisionSummaries(function(summaries: { Summary })
			readSummaries(self, instance, pieceId, cooldowns, summaries)
		end)
	)
end

-- Se suscribe a las cajas que ya tiene el auto y a las que le lleguen después (el modelo se replica de a partes).
function CollisionReader.bind(self: CollisionReader, vehicle: Model)
	self:unbind()
	for _, child in vehicle:GetChildren() do
		bindPart(self, child)
	end
	table.insert(
		self._connections,
		vehicle.ChildAdded:Connect(function(child)
			bindPart(self, child)
		end)
	)
end

function CollisionReader.unbind(self: CollisionReader)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

return CollisionReader
