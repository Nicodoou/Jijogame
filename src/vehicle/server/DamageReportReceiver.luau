--!strict
-- Recibe el estado de daño que manda el cliente dueño del auto (WP-18). El servidor no lo usa todavía: valida el
-- mensaje (tipo, rangos, quién lo manda, si tiene auto y la frecuencia) y lo deja registrado, preparado para cuando el
-- desgaste se guarde entre partidas.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DamageConfig = require(ReplicatedStorage.vehicle.core.damage.DamageConfig)
local DamageReport = require(ReplicatedStorage.vehicle.core.damage.DamageReport)
local DamageTypes = require(ReplicatedStorage.vehicle.core.damage.DamageTypes)
local VehicleParts = require(ReplicatedStorage.vehicle.shared.VehicleParts)

type DamageState = DamageTypes.DamageState

local DamageReportReceiver = {}
DamageReportReceiver.__index = DamageReportReceiver

export type DamageReportReceiver = typeof(setmetatable(
	{} :: {
		_remote: RemoteEvent,
		_states: { [Player]: DamageState },
		_lastReportSeconds: { [Player]: number },
	},
	DamageReportReceiver
))

function DamageReportReceiver.new(): DamageReportReceiver
	local remote = Instance.new("RemoteEvent")
	remote.Name = VehicleParts.DAMAGE_REPORT_REMOTE_NAME
	remote.Parent = ReplicatedStorage
	local self = setmetatable({ _remote = remote, _states = {}, _lastReportSeconds = {} }, DamageReportReceiver)
	remote.OnServerEvent:Connect(function(player: Player, payload: unknown)
		self:handleReport(player, payload)
	end)
	return self
end

-- Registra el intento aunque el mensaje sea inválido, así la frecuencia limita también los mensajes repetidos.
local function isWithinRateLimit(self: DamageReportReceiver, player: Player, nowSeconds: number): boolean
	local last = self._lastReportSeconds[player]
	self._lastReportSeconds[player] = nowSeconds
	return last == nil or nowSeconds - last >= DamageConfig.HITBOX.REPORT_ACCEPT_SECONDS
end

local function hasVehicle(player: Player): boolean
	return Workspace:FindFirstChild(VehicleParts.modelName(player.UserId)) ~= nil
end

-- Los mensajes inválidos se ignoran sin error. Es público para poder probarlo con un jugador simulado.
function DamageReportReceiver.handleReport(self: DamageReportReceiver, player: Player, payload: unknown)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	if not isWithinRateLimit(self, player, os.clock()) or not hasVehicle(player) then
		return
	end
	local state = DamageReport.validate(payload, DamageConfig.PIECES)
	if state ~= nil then
		self._states[player] = state
	end
end

function DamageReportReceiver.getState(self: DamageReportReceiver, player: Player): DamageState?
	return self._states[player]
end

function DamageReportReceiver.clear(self: DamageReportReceiver, player: Player)
	self._states[player] = nil
	self._lastReportSeconds[player] = nil
end

return DamageReportReceiver
