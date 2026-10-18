--!strict
-- Lleva el estado de daño del auto propio (WP-18): aplica cada golpe con el modelo de daño del núcleo, avisa los eventos
-- y entrega la configuración del simulador con los efectos del daño ya aplicados (`DamageEffects`).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DamageEffects = require(ReplicatedStorage.vehicle.core.damage.DamageEffects)
local DamageModel = require(ReplicatedStorage.vehicle.core.damage.DamageModel)
local DamageTypes = require(ReplicatedStorage.vehicle.core.damage.DamageTypes)
local VehicleTypes = require(ReplicatedStorage.vehicle.core.VehicleTypes)

type DamageEvent = DamageTypes.DamageEvent
type DamageState = DamageTypes.DamageState
type PieceSpecs = DamageTypes.PieceSpecs
type VehicleSettings = VehicleTypes.VehicleSettings

export type DamageListener = (event: DamageEvent) -> ()

local DamageController = {}
DamageController.__index = DamageController

export type DamageController = typeof(setmetatable(
	{} :: {
		_specs: PieceSpecs,
		_state: DamageState,
		_listeners: { DamageListener },
		_hasDamage: boolean,
		-- La última configuración con daño y la base de la que salió: mientras el daño no cambie, se reutiliza.
		_cachedBase: VehicleSettings?,
		_cachedResult: VehicleSettings?,
	},
	DamageController
))

function DamageController.new(specs: PieceSpecs): DamageController
	return setmetatable({
		_specs = specs,
		_state = DamageModel.newState(specs),
		_listeners = {},
		_hasDamage = false,
		_cachedBase = nil,
		_cachedResult = nil,
	}, DamageController)
end

function DamageController.onEvent(self: DamageController, listener: DamageListener)
	table.insert(self._listeners, listener)
end

function DamageController.getState(self: DamageController): DamageState
	return self._state
end

-- Un golpe en la caja de `pieceId`. Los eventos que produce se avisan a los oyentes en orden.
function DamageController.applyHit(self: DamageController, pieceId: string, impactSpeed: number)
	local nextState, events = DamageModel.applyImpact(self._state, pieceId, impactSpeed, self._specs)
	self._state = nextState
	if #events == 0 then
		return
	end
	self._hasDamage = true
	self._cachedResult = nil
	for _, event in events do
		for _, listener in self._listeners do
			listener(event)
		end
	end
end

-- Con el auto sano devuelve la misma configuración que recibe; con daño, la copia con los efectos.
function DamageController.adjustConfig(self: DamageController, settings: VehicleSettings): VehicleSettings
	if not self._hasDamage then
		return settings
	end
	local cached = self._cachedResult
	if cached == nil or self._cachedBase ~= settings then
		cached = DamageEffects.apply(settings, self._state, self._specs)
		self._cachedBase, self._cachedResult = settings, cached
	end
	return cached :: VehicleSettings
end

-- Auto nuevo: el daño vuelve a 0.
function DamageController.reset(self: DamageController)
	self._state = DamageModel.newState(self._specs)
	self._hasDamage = false
	self._cachedBase, self._cachedResult = nil, nil
end

return DamageController
