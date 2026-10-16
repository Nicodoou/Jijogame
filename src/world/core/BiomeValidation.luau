--!strict
-- Chequeo de forma de las fichas de bioma. Devuelve la lista de problemas (vacía si todo está bien).
-- Las fichas llegan como datos sin garantías: cada chequeo mira también que existan las tablas que revisa.

local BiomeTypes = require("./BiomeTypes")

type BiomeDefinition = BiomeTypes.BiomeDefinition
type Report = (string) -> ()

local PROPORTION_SUM_TOLERANCE = 1e-6
local CLIMATE_AXES = { "relief", "humidity", "temperature" }
-- Superficies de la ruta: una ficha no puede darlas fuera de ella.
local ROAD_ONLY_SURFACES: { [unknown]: boolean } = { Road = true, Shoulder = true }

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function isNonEmptyString(value: unknown): boolean
	return type(value) == "string" and value ~= ""
end

local function isOffroadSurface(value: unknown): boolean
	return isNonEmptyString(value) and not ROAD_ONLY_SURFACES[value]
end

local function checkClimate(climate: any, report: Report)
	for _, axis in CLIMATE_AXES do
		local range = if type(climate) == "table" then climate[axis] else nil
		local isWellFormed = type(range) == "table"
			and isFiniteNumber(range.min)
			and isFiniteNumber(range.max)
			and range.min >= 0
			and range.max <= 1
			and range.min <= range.max
		if not isWellFormed then
			report(`climate.{axis} needs 0 <= min <= max <= 1`)
		end
	end
end

local function checkTerrain(terrain: any, report: Report)
	if type(terrain) ~= "table" then
		report("terrain is missing")
		return
	end
	if not (isFiniteNumber(terrain.hillAmplitudeScale) and terrain.hillAmplitudeScale >= 0) then
		report("terrain.hillAmplitudeScale has to be a finite number >= 0")
	end
	if not (isFiniteNumber(terrain.hillRoughness) and terrain.hillRoughness > 0) then
		report("terrain.hillRoughness has to be a finite number > 0")
	end
end

local function checkSurfaceShares(shares: any, report: Report)
	if type(shares) ~= "table" or #shares == 0 then
		report("materials.surface needs at least one material")
		return
	end
	local proportionSum = 0
	for _, share in shares do
		if
			type(share) == "table"
			and isNonEmptyString(share.material)
			and isFiniteNumber(share.proportion)
			and share.proportion > 0
		then
			proportionSum += share.proportion
		else
			report("every materials.surface entry needs a material name and a proportion > 0")
		end
	end
	if math.abs(proportionSum - 1) > PROPORTION_SUM_TOLERANCE then
		report("the materials.surface proportions have to add up to 1")
	end
end

local function checkMaterials(materials: any, report: Report)
	if type(materials) ~= "table" then
		report("materials is missing")
		return
	end
	if not isNonEmptyString(materials.transition) then
		report("materials.transition has to be a non-empty string")
	end
	if not isNonEmptyString(materials.deep) then
		report("materials.deep has to be a non-empty string")
	end
	checkSurfaceShares(materials.surface, report)
end

local function isWellFormedPatch(patch: any): boolean
	return type(patch) == "table"
		and isOffroadSurface(patch.surface)
		and isFiniteNumber(patch.noiseScalePerStud)
		and patch.noiseScalePerStud > 0
		and isFiniteNumber(patch.noiseThreshold)
		and isFiniteNumber(patch.minDistanceFromShoulderStuds)
		and patch.minDistanceFromShoulderStuds >= 0
end

local function checkSurfaces(surfaces: any, report: Report)
	if type(surfaces) ~= "table" then
		report("surfaces is missing")
		return
	end
	if not isOffroadSurface(surfaces.offroad) then
		report("surfaces.offroad has to be a surface that is not Road or Shoulder")
	end
	if type(surfaces.patches) ~= "table" then
		report("surfaces.patches is missing")
		return
	end
	for _, patch in surfaces.patches do
		if not isWellFormedPatch(patch) then
			report(
				"every surfaces.patches entry needs a surface other than Road or Shoulder, a scale > 0, a threshold and a distance >= 0"
			)
		end
	end
end

local function isWellFormedDecoration(entry: any): boolean
	return type(entry) == "table"
		and isNonEmptyString(entry.kind)
		and isFiniteNumber(entry.density)
		and entry.density >= 0
		and isFiniteNumber(entry.minSpacingStuds)
		and entry.minSpacingStuds > 0
		and isNonEmptyString(entry.collision)
end

local function checkDecoration(decoration: any, report: Report)
	if type(decoration) ~= "table" then
		report("decoration is missing")
		return
	end
	for _, entry in decoration do
		if not isWellFormedDecoration(entry) then
			report("every decoration entry needs a kind, a density >= 0, a spacing > 0 and a collision shape")
		end
	end
end

local function checkDefinition(definition: any, seenIds: { [string]: boolean }, report: Report)
	if isNonEmptyString(definition.id) then
		if seenIds[definition.id] then
			report("the id is repeated")
		end
		seenIds[definition.id] = true
	else
		report("the id has to be a non-empty string")
	end
	checkClimate(definition.climate, report)
	checkTerrain(definition.terrain, report)
	checkMaterials(definition.materials, report)
	checkSurfaces(definition.surfaces, report)
	checkDecoration(definition.decoration, report)
end

local BiomeValidation = {}

function BiomeValidation.validate(definitions: { BiomeDefinition }): { string }
	local problems: { string } = {}
	if #definitions == 0 then
		table.insert(problems, "the catalog needs at least one biome")
	end
	local seenIds: { [string]: boolean } = {}
	for index, definition in definitions do
		local label = if isNonEmptyString(definition.id) then definition.id else `#{index}`
		checkDefinition(definition, seenIds, function(message: string)
			table.insert(problems, `{label}: {message}`)
		end)
	end
	return problems
end

return BiomeValidation
