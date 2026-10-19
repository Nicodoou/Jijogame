--!strict
-- Valores de ajuste del auto: la combinación fija del MVP (decisión E1), armada con `VehicleBuild` desde las fichas del
-- 147, su motor y su caja automática. Los valores viven en `specs/`; el simulador sigue leyendo esta misma tabla.
local Automatic5 = require("./specs/gearboxes/Automatic5")
local Engine147 = require("./specs/engines/Engine147")
local Fiat147 = require("./specs/cars/Fiat147")
local VehicleBuild = require("./VehicleBuild")

local settings, problem = VehicleBuild.assemble(Fiat147, Engine147, Automatic5)

-- Si la combinación es inválida, el error trae la razón que dio `assemble`.
return (assert(settings, problem))
