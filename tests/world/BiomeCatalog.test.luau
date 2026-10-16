--!strict
local BiomeCatalog = require("../../src/world/core/BiomeCatalog")
local BiomeTestCatalog = require("./BiomeTestCatalog")
local Runner = require("../Runner")
local WorldConfig = require("../../src/world/core/WorldConfig")

type Mutation = (any) -> ()

local function expectInvalid(mutate: Mutation, label: string)
	local broken = BiomeTestCatalog.copyDefinition(BiomeCatalog.forest)
	mutate(broken)
	local problems = BiomeCatalog.validate({ broken })
	if #problems == 0 then
		error(`the broken definition was accepted: {label}`, 0)
	end
end

Runner.test("forest is a valid catalog by itself", function()
	Runner.expectEqual(#BiomeCatalog.validate({ BiomeCatalog.forest }), 0)
	Runner.expectEqual(#BiomeCatalog.validate(BiomeCatalog.all), 0)
end)

Runner.test("the game catalog has only forest", function()
	Runner.expectEqual(#BiomeCatalog.all, 1)
	Runner.expectEqual(BiomeCatalog.all[1], BiomeCatalog.forest)
	Runner.expectEqual(BiomeCatalog.forest.id, "forest")
end)

Runner.test("forest reproduces the surface, the mud patches and the materials of today", function()
	local forest = BiomeCatalog.forest
	Runner.expectEqual(forest.surfaces.offroad, "Grass")
	Runner.expectEqual(#forest.surfaces.patches, 1)
	local mud = forest.surfaces.patches[1]
	Runner.expectEqual(mud.surface, "Mud")
	Runner.expectEqual(mud.noiseScalePerStud, WorldConfig.MUD_NOISE_SCALE_PER_STUD)
	Runner.expectEqual(mud.noiseThreshold, WorldConfig.MUD_NOISE_THRESHOLD)
	Runner.expectEqual(mud.minDistanceFromShoulderStuds, WorldConfig.MUD_MIN_DISTANCE_FROM_SHOULDER_STUDS)
	Runner.expectEqual(forest.materials.surface[1].material, "Grass")
	Runner.expectEqual(forest.materials.surface[2].material, "LeafyGrass")
	Runner.expectEqual(forest.materials.transition, "Ground")
	Runner.expectEqual(forest.materials.deep, "Ground")
end)

Runner.test("forest covers the whole climate, so it never loses weight to anything", function()
	for _, range in
		{
			BiomeCatalog.forest.climate.relief,
			BiomeCatalog.forest.climate.humidity,
			BiomeCatalog.forest.climate.temperature,
		}
	do
		Runner.expectEqual(range.min, 0)
		Runner.expectEqual(range.max, 1)
	end
end)

Runner.test("forest is read only, even its inner tables", function()
	Runner.expectError(function()
		(BiomeCatalog.forest :: any).id = "other"
	end)
	Runner.expectError(function()
		(BiomeCatalog.forest.climate.relief :: any).max = 0.5
	end)
	Runner.expectError(function()
		(BiomeCatalog.forest.materials.surface[1] :: any).proportion = 1
	end)
	Runner.expectError(function()
		(BiomeCatalog :: any).forest = nil
	end)
end)

Runner.test("the fictional catalogs of the tests are valid, alone and together", function()
	Runner.expectEqual(#BiomeCatalog.validate(BiomeTestCatalog.pair), 0)
	Runner.expectEqual(#BiomeCatalog.validate(BiomeTestCatalog.triple), 0)
	Runner.expectEqual(#BiomeCatalog.validate({ BiomeTestCatalog.lowland }), 0)
end)

Runner.test("an empty catalog is not valid", function()
	Runner.expectEqual(#BiomeCatalog.validate({}) > 0, true)
end)

Runner.test("a repeated id is not valid", function()
	Runner.expectEqual(#BiomeCatalog.validate({ BiomeCatalog.forest, BiomeCatalog.forest }) > 0, true)
end)

Runner.test("a definition without a usable id is not valid", function()
	expectInvalid(function(definition)
		definition.id = ""
	end, "empty id")
	expectInvalid(function(definition)
		definition.id = nil
	end, "missing id")
	expectInvalid(function(definition)
		definition.id = 7
	end, "id that is not a string")
end)

Runner.test("a climate box that is out of order, out of [0, 1] or not a number is not valid", function()
	for _, axis in { "relief", "humidity", "temperature" } do
		expectInvalid(function(definition)
			definition.climate[axis] = { min = 0.6, max = 0.4 }
		end, `{axis} min above max`)
		expectInvalid(function(definition)
			definition.climate[axis].min = -0.01
		end, `{axis} min below 0`)
		expectInvalid(function(definition)
			definition.climate[axis].max = 1.01
		end, `{axis} max above 1`)
		expectInvalid(function(definition)
			definition.climate[axis].max = 0 / 0
		end, `{axis} max is NaN`)
		expectInvalid(function(definition)
			definition.climate[axis] = nil
		end, `{axis} missing`)
	end
	expectInvalid(function(definition)
		definition.climate = nil
	end, "no climate")
end)

Runner.test("a climate box can be a single point or the whole range", function()
	local point = BiomeTestCatalog.copyDefinition(BiomeCatalog.forest)
	point.climate.relief = { min = 0.5, max = 0.5 }
	Runner.expectEqual(#BiomeCatalog.validate({ point }), 0)
end)

Runner.test("terrain scales that are negative, zero roughness or not numbers are not valid", function()
	expectInvalid(function(definition)
		definition.terrain.hillAmplitudeScale = -1
	end, "negative amplitude")
	expectInvalid(function(definition)
		definition.terrain.hillRoughness = 0
	end, "zero roughness")
	expectInvalid(function(definition)
		definition.terrain.hillRoughness = math.huge
	end, "infinite roughness")
	expectInvalid(function(definition)
		definition.terrain = nil
	end, "no terrain")
	local flat = BiomeTestCatalog.copyDefinition(BiomeCatalog.forest)
	flat.terrain.hillAmplitudeScale = 0
	Runner.expectEqual(#BiomeCatalog.validate({ flat }), 0)
end)

Runner.test("materials with bad proportions, empty names or no materials at all are not valid", function()
	expectInvalid(function(definition)
		definition.materials.surface[1].proportion = 0.5
	end, "proportions that do not add up to 1")
	expectInvalid(function(definition)
		definition.materials.surface[1].proportion = 0
		definition.materials.surface[2].proportion = 1
	end, "a proportion of 0")
	expectInvalid(function(definition)
		definition.materials.surface[1].proportion = -0.2
		definition.materials.surface[2].proportion = 1.2
	end, "a negative proportion")
	expectInvalid(function(definition)
		definition.materials.surface[1].material = ""
	end, "empty material name")
	expectInvalid(function(definition)
		definition.materials.surface = {}
	end, "no surface materials")
	expectInvalid(function(definition)
		definition.materials.surface = nil
	end, "missing surface list")
	expectInvalid(function(definition)
		definition.materials.transition = ""
	end, "empty transition")
	expectInvalid(function(definition)
		definition.materials.deep = nil
	end, "missing deep")
	expectInvalid(function(definition)
		definition.materials = nil
	end, "no materials")
end)

Runner.test("surfaces that are the road, a bad patch or missing are not valid", function()
	expectInvalid(function(definition)
		definition.surfaces.offroad = "Road"
	end, "offroad Road")
	expectInvalid(function(definition)
		definition.surfaces.offroad = "Shoulder"
	end, "offroad Shoulder")
	expectInvalid(function(definition)
		definition.surfaces.patches[1].surface = "Road"
	end, "patch Road")
	expectInvalid(function(definition)
		definition.surfaces.patches[1].noiseScalePerStud = 0
	end, "patch scale 0")
	expectInvalid(function(definition)
		definition.surfaces.patches[1].noiseThreshold = 0 / 0
	end, "patch threshold NaN")
	expectInvalid(function(definition)
		definition.surfaces.patches[1].minDistanceFromShoulderStuds = -1
	end, "negative patch distance")
	expectInvalid(function(definition)
		definition.surfaces.patches = nil
	end, "missing patches")
	expectInvalid(function(definition)
		definition.surfaces = nil
	end, "no surfaces")
	local noPatches = BiomeTestCatalog.copyDefinition(BiomeCatalog.forest)
	noPatches.surfaces.patches = {}
	Runner.expectEqual(#BiomeCatalog.validate({ noPatches }), 0)
end)

local function countProblemsWithEntry(entry: any): number
	local definition = BiomeTestCatalog.copyDefinition(BiomeCatalog.forest)
	definition.decoration = { entry }
	return #BiomeCatalog.validate({ definition })
end

Runner.test("a well formed decoration entry is valid, with density zero too", function()
	local entry = { kind = "Tree", density = 0.01, minSpacingStuds = 6, collision = "sphere" }
	Runner.expectEqual(countProblemsWithEntry(entry), 0)
	entry.density = 0
	Runner.expectEqual(countProblemsWithEntry(entry), 0)
end)

Runner.test("decoration entries with a bad kind, density, spacing or shape are not valid", function()
	local bad: { any } = {
		{ kind = "", density = 0.01, minSpacingStuds = 6, collision = "sphere" },
		{ kind = "Tree", density = -0.01, minSpacingStuds = 6, collision = "sphere" },
		{ kind = "Tree", density = 0.01, minSpacingStuds = 0, collision = "sphere" },
		{ kind = "Tree", density = 0.01, minSpacingStuds = 6, collision = "" },
		{ kind = "Tree", density = 0 / 0, minSpacingStuds = 6, collision = "sphere" },
		{ density = 0.01, minSpacingStuds = 6, collision = "sphere" },
	}
	for _, entry in bad do
		Runner.expectEqual(countProblemsWithEntry(entry) > 0, true)
	end
	expectInvalid(function(definition)
		definition.decoration = nil
	end, "no decoration")
end)

Runner.test("each problem names the definition that has it", function()
	local broken = BiomeTestCatalog.copyDefinition(BiomeTestCatalog.lowland)
	broken.terrain.hillRoughness = 0
	local problems = BiomeCatalog.validate({ BiomeCatalog.forest, broken })
	Runner.expectEqual(#problems, 1)
	Runner.expectEqual(string.sub(problems[1], 1, #"lowland:"), "lowland:")
end)

Runner.finish()
