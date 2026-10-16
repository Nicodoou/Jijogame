--!strict
-- Oculta, solo en este cliente, las piezas del propio auto que tapan la vista desde la cabeza del conductor.
local OwnVehicleVisibility = {}
OwnVehicleVisibility.__index = OwnVehicleVisibility

-- El volante del 147 es un disco macizo a 0,75 studs de la cámara y tapa el 26% de la pantalla (medido en Studio).
local HIDDEN_PART_NAMES = { "Steering wheel" }
local FULLY_HIDDEN = 1

export type OwnVehicleVisibility = typeof(setmetatable({} :: { _lastModel: Model? }, OwnVehicleVisibility))

function OwnVehicleVisibility.new(): OwnVehicleVisibility
	return setmetatable({ _lastModel = nil }, OwnVehicleVisibility)
end

-- Se llama en cada cuadro, pero solo trabaja cuando aparece un auto nuevo.
function OwnVehicleVisibility.step(self: OwnVehicleVisibility, vehicleModel: Model?)
	if vehicleModel == nil or vehicleModel == self._lastModel then
		return
	end
	self._lastModel = vehicleModel
	for _, descendant in vehicleModel:GetDescendants() do
		if descendant:IsA("BasePart") and table.find(HIDDEN_PART_NAMES, descendant.Name) ~= nil then
			descendant.LocalTransparencyModifier = FULLY_HIDDEN
		end
	end
end

return OwnVehicleVisibility
