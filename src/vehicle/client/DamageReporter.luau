--!strict
-- Le manda al servidor el estado de daño (WP-18), como mucho una vez cada `REPORT_INTERVAL_SECONDS` y solo si cambió.
-- El servidor valida el mensaje y lo registra; el daño se calcula en el cliente, que es quien recibe los golpes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DamageConfig = require(ReplicatedStorage.vehicle.core.damage.DamageConfig)
local DamageTypes = require(ReplicatedStorage.vehicle.core.damage.DamageTypes)
local VehicleParts = require(ReplicatedStorage.vehicle.shared.VehicleParts)

type DamageState = DamageTypes.DamageState

local DamageReporter = {}
DamageReporter.__index = DamageReporter

export type DamageReporter = typeof(setmetatable(
	{} :: {
		_remote: RemoteEvent?,
		_hasChanged: boolean,
		_lastSentSeconds: number?,
	},
	DamageReporter
))

function DamageReporter.new(): DamageReporter
	return setmetatable({ _remote = nil, _hasChanged = false, _lastSentSeconds = nil }, DamageReporter)
end

function DamageReporter.markChanged(self: DamageReporter)
	self._hasChanged = true
end

-- Una vez por cuadro. El evento remoto puede no existir todavía: se vuelve a buscar en el cuadro siguiente.
function DamageReporter.step(self: DamageReporter, state: DamageState, nowSeconds: number)
	local last = self._lastSentSeconds
	if not self._hasChanged or (last ~= nil and nowSeconds - last < DamageConfig.HITBOX.REPORT_INTERVAL_SECONDS) then
		return
	end
	local remote = self._remote or ReplicatedStorage:FindFirstChild(VehicleParts.DAMAGE_REPORT_REMOTE_NAME)
	if remote == nil or not remote:IsA("RemoteEvent") then
		return
	end
	self._remote = remote
	remote:FireServer({ pieces = state.pieces })
	self._hasChanged = false
	self._lastSentSeconds = nowSeconds
end

return DamageReporter
