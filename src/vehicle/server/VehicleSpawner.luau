--!strict
-- Crea el auto anclado de cada jugador y lo suelta cuando el cliente avisa que el mundo está listo (RN-2).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RoadPoint = require(ReplicatedStorage.shared.contracts.RoadPoint)
local Suspension = require(ReplicatedStorage.vehicle.core.Suspension)
local TuningOverrides = require(ReplicatedStorage.vehicle.shared.TuningOverrides)
local VectorConversion = require(ReplicatedStorage.vehicle.shared.VectorConversion)
local VehicleParts = require(ReplicatedStorage.vehicle.shared.VehicleParts)
local VehicleTypes = require(ReplicatedStorage.vehicle.core.VehicleTypes)
local VehicleModelBuilder = require("./VehicleModelBuilder")

type VehicleSettings = VehicleTypes.VehicleSettings

type Vehicle = {
	model: Model,
	body: BasePart,
}

local RELEASE_REQUEST_INTERVAL_SECONDS = 1
-- La compresión estática no depende de la masa: se cancela entre la carga y la rigidez.
local UNIT_MASS = 1

local VehicleSpawner = {}
VehicleSpawner.__index = VehicleSpawner

export type VehicleSpawner = typeof(setmetatable(
	{} :: {
		_getSpawnPoint: RoadPoint.GetSpawnPoint,
		_tuning: TuningOverrides.TuningOverrides<VehicleSettings>,
		_vehicles: { [Player]: Vehicle },
		_lastRequestSeconds: { [Player]: number },
		_remote: RemoteEvent,
	},
	VehicleSpawner
))

function VehicleSpawner.new(getSpawnPoint: RoadPoint.GetSpawnPoint, config: VehicleSettings): VehicleSpawner
	local remote = Instance.new("RemoteEvent")
	remote.Name = VehicleParts.RELEASE_REMOTE_NAME
	remote.Parent = ReplicatedStorage
	local self = setmetatable({
		_getSpawnPoint = getSpawnPoint,
		_tuning = TuningOverrides.new(config, Workspace, RunService:IsStudio()),
		_vehicles = {},
		_lastRequestSeconds = {},
		_remote = remote,
	}, VehicleSpawner)
	remote.OnServerEvent:Connect(function(player: Player)
		self:handleReleaseRequest(player)
	end)
	return self
end

-- Altura del centro del chasis sobre el suelo con las ruedas a la compresión estática.
local function restingHeightStuds(config: VehicleSettings): number
	local wheelCount = #config.WHEELS
	local staticCompression = Suspension.staticLoad(UNIT_MASS, Workspace.Gravity, wheelCount)
		/ Suspension.springRate(UNIT_MASS, wheelCount, config)
	local mountHeight = -config.WHEELS[1].offset.y
	return mountHeight + config.SUSPENSION_REST_LENGTH_STUDS + config.WHEEL_RADIUS_STUDS - staticCompression
end

local function restingCFrame(spawnPoint: RoadPoint.RoadPoint, config: VehicleSettings): CFrame
	local position = VectorConversion.toVector3(spawnPoint.position)
	local direction = VectorConversion.toVector3(spawnPoint.direction)
	local raised = position + Vector3.yAxis * restingHeightStuds(config)
	return CFrame.lookAt(raised, raised + direction)
end

function VehicleSpawner.spawnFor(self: VehicleSpawner, player: Player)
	self:despawnFor(player)
	-- Los Cfg_ del servidor (solo en Studio) se aplican al aparecer: el lastre se arma ahora.
	local config = self._tuning:getConfig()
	local bodyCFrame = restingCFrame(self._getSpawnPoint(), config)
	local model = VehicleModelBuilder.build(player.UserId, bodyCFrame, config)
	model.Parent = Workspace
	local body = model.PrimaryPart :: BasePart
	-- El cliente tiene que ver el auto aunque esté lejos, o el streaming lo oculta.
	player.ReplicationFocus = body
	self._vehicles[player] = { model = model, body = body }
end

function VehicleSpawner.despawnFor(self: VehicleSpawner, player: Player)
	local vehicle = self._vehicles[player]
	if vehicle ~= nil then
		vehicle.model:Destroy()
	end
	self._vehicles[player] = nil
	self._lastRequestSeconds[player] = nil
end

-- Registra el pedido aunque sea inválido, así la frecuencia limita también los pedidos repetidos.
local function isWithinRateLimit(self: VehicleSpawner, player: Player): boolean
	local now = os.clock()
	local last = self._lastRequestSeconds[player]
	self._lastRequestSeconds[player] = now
	return last == nil or now - last >= RELEASE_REQUEST_INTERVAL_SECONDS
end

local function ownsAnchoredVehicle(self: VehicleSpawner, player: Player): boolean
	local vehicle = self._vehicles[player]
	if vehicle == nil then
		return false
	end
	local isOwner = vehicle.model:GetAttribute(VehicleParts.OWNER_ATTRIBUTE) == player.UserId
	return isOwner and vehicle.body.Anchored
end

-- Los pedidos inválidos se ignoran sin error. Es público para poder probarlo con un jugador simulado.
function VehicleSpawner.handleReleaseRequest(self: VehicleSpawner, player: Player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	if not isWithinRateLimit(self, player) or not ownsAnchoredVehicle(self, player) then
		return
	end
	local body = self._vehicles[player].body
	body.Anchored = false
	body:SetNetworkOwner(player)
end

return VehicleSpawner
