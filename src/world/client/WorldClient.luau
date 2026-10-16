--!strict
-- Raíz de composición del mundo en el cliente: arma el planificador del núcleo con el Terrain real y el presupuesto
-- de trabajo, y devuelve los cuatro contratos más `step`, que el arranque engancha a cada frame.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RoadPoint = require(ReplicatedStorage.shared.contracts.RoadPoint)
local Surface = require(ReplicatedStorage.shared.contracts.Surface)
local VehiclePosition = require(ReplicatedStorage.shared.contracts.VehiclePosition)
local WorkBudget = require(ReplicatedStorage.world.core.WorkBudget)
local WorldConfig = require(ReplicatedStorage.world.core.WorldConfig)
local WorldPlanner = require(ReplicatedStorage.world.core.WorldPlanner)
local WorldReady = require(ReplicatedStorage.shared.contracts.WorldReady)
local TerrainWriter = require("./TerrainWriter")

export type Dependencies = {
	seed: number,
	getVehiclePosition: VehiclePosition.GetVehiclePosition,
	-- Devuelve milisegundos. Por defecto, os.clock.
	clock: (() -> number)?,
}

export type WorldClient = {
	-- Una vez por frame: avisa dónde está el auto y avanza el trabajo del mundo dentro del presupuesto.
	step: () -> (),
	getSurfaceAt: Surface.GetSurfaceAt,
	getNearestRoadPoint: RoadPoint.GetNearestRoadPoint,
	getSpawnPoint: RoadPoint.GetSpawnPoint,
	isWorldReadyAt: WorldReady.IsWorldReadyAt,
	getStatus: () -> WorldPlanner.WorldStatus,
}

-- Mismo nombre que publica WorldSeedServer.
local SEED_ATTRIBUTE_NAME = "WorldSeed"
local MILLISECONDS_PER_SECOND = 1000
local PROFILE_LABEL = "WorldClient.step"

local WorldClientModule = {}

local function readClockMilliseconds(): number
	return os.clock() * MILLISECONDS_PER_SECOND
end

-- Espera hasta que el servidor publique la semilla.
function WorldClientModule.waitForSeed(): number
	local seed = ReplicatedStorage:GetAttribute(SEED_ATTRIBUTE_NAME)
	while type(seed) ~= "number" do
		ReplicatedStorage:GetAttributeChangedSignal(SEED_ATTRIBUTE_NAME):Wait()
		seed = ReplicatedStorage:GetAttribute(SEED_ATTRIBUTE_NAME)
	end
	return seed
end

function WorldClientModule.new(dependencies: Dependencies): WorldClient
	local getVehiclePosition = dependencies.getVehiclePosition
	local planner = WorldPlanner.new({
		seed = dependencies.seed,
		sink = TerrainWriter.new(Workspace.Terrain),
	})
	local budget = WorkBudget.new(dependencies.clock or readClockMilliseconds, WorldConfig.WORK_BUDGET_MS_PER_FRAME)

	local function step()
		debug.profilebegin(PROFILE_LABEL)
		planner.updatePlan(getVehiclePosition())
		budget.advance(planner)
		debug.profileend()
	end

	return {
		step = step,
		getSurfaceAt = planner.getSurfaceAt,
		getNearestRoadPoint = planner.getNearestRoadPoint,
		getSpawnPoint = planner.getSpawnPoint,
		isWorldReadyAt = planner.isWorldReadyAt,
		getStatus = planner.getStatus,
	}
end

return WorldClientModule
