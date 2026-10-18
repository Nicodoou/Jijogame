--!strict
-- Arma el daño del auto propio en el cliente (WP-18): une el controlador de daño con la lectura de golpes, lo que se ve
-- y el reporte al servidor. Cuando aparece un auto nuevo (el modelo cambia) el daño vuelve a 0.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DamageTypes = require(ReplicatedStorage.vehicle.core.damage.DamageTypes)
local VehicleModels = require(ReplicatedStorage.vehicle.core.VehicleModels)
local CollisionReader = require("./CollisionReader")
local DamageController = require("./DamageController")
local DamageReporter = require("./DamageReporter")
local DamageVisuals = require("./DamageVisuals")

type DamageEvent = DamageTypes.DamageEvent

local DamageClient = {}
DamageClient.__index = DamageClient

export type DamageClient = typeof(setmetatable(
	{} :: {
		_controller: DamageController.DamageController,
		_reader: CollisionReader.CollisionReader,
		_reporter: DamageReporter.DamageReporter,
		_getModel: () -> Model?,
		_clock: () -> number,
		_model: Model?,
		_visuals: DamageVisuals.DamageVisuals?,
	},
	DamageClient
))

function DamageClient.new(
	controller: DamageController.DamageController,
	specs: DamageTypes.PieceSpecs,
	getModel: () -> Model?,
	clock: () -> number
): DamageClient
	local reporter = DamageReporter.new()
	local self = setmetatable({
		_controller = controller,
		_reader = CollisionReader.new(specs, function(pieceId: string, impactSpeed: number)
			controller:applyHit(pieceId, impactSpeed)
		end, clock),
		_reporter = reporter,
		_getModel = getModel,
		_clock = clock,
		_model = nil,
		_visuals = nil,
	}, DamageClient)
	controller:onEvent(function(event: DamageEvent)
		reporter:markChanged()
		if self._visuals ~= nil then
			self._visuals:handleEvent(event, clock())
		end
	end)
	return self
end

-- Auto nuevo (o ninguno): suelta lo del anterior, pone el daño en 0 y se suscribe a las cajas del nuevo.
local function switchModel(self: DamageClient, model: Model?)
	self._reader:unbind()
	if self._visuals ~= nil then
		self._visuals:destroy()
		self._visuals = nil
	end
	self._controller:reset()
	self._reporter:markChanged()
	self._model = model
	if model ~= nil then
		self._visuals = DamageVisuals.new(model, VehicleModels.Fiat147)
		self._reader:bind(model)
	end
end

-- Una vez por cuadro.
function DamageClient.step(self: DamageClient)
	local model = self._getModel()
	if model ~= self._model then
		switchModel(self, model)
	end
	local now = self._clock()
	if self._visuals ~= nil then
		self._visuals:step(now)
	end
	self._reporter:step(self._controller:getState(), now)
end

return DamageClient
