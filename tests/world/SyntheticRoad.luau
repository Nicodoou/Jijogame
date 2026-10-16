--!strict
-- Rutas inventadas para las pruebas del terreno: se arman a partir de funciones de curvatura y de altura, con el mismo
-- formato de tramos que RoadPath, y una ruta falsa que los entrega en orden. No es una prueba: no termina en
-- Runner.finish().

local RoadFrame = require("../../src/world/core/RoadFrame")
local RoadPath = require("../../src/world/core/RoadPath")
local WorldConfig = require("../../src/world/core/WorldConfig")

export type Layout = {
	segmentCount: number,
	-- Índice del primer tramo. Los números de paso siguen contando desde el comienzo de la ruta.
	firstSegmentIndex: number?,
	startX: number,
	startZ: number,
	startHeadingRadians: number,
	-- Curvatura (1/stud, positiva hacia la derecha) y altura del eje en cada paso de integración.
	curvatureAt: (step: number) -> number,
	heightAt: (step: number) -> number,
}

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local STEPS_PER_SEGMENT = RoadFrame.getStepsPerSegment()

local SyntheticRoad = {}

SyntheticRoad.STEPS_PER_SEGMENT = STEPS_PER_SEGMENT

function SyntheticRoad.createSegments(layout: Layout): { RoadPath.Segment }
	local firstIndex = layout.firstSegmentIndex or 0
	local x, z, heading = layout.startX, layout.startZ, layout.startHeadingRadians
	local segments: { RoadPath.Segment } = {}
	for offset = 0, layout.segmentCount - 1 do
		local firstStep = (firstIndex + offset) * STEPS_PER_SEGMENT
		local samples: { RoadPath.RoadSample } = {}
		for stepInSegment = 0, STEPS_PER_SEGMENT do
			local step = firstStep + stepInSegment
			local height = layout.heightAt(step)
			samples[stepInSegment + 1] = {
				position = vector.create(x, height, z),
				heading = heading,
				curvature = layout.curvatureAt(step),
				slope = math.atan((layout.heightAt(step + 1) - height) / STEP_STUDS),
				arcLength = step * STEP_STUDS,
			}
			heading += layout.curvatureAt(step) * STEP_STUDS
			x += STEP_STUDS * math.cos(heading)
			z += STEP_STUDS * math.sin(heading)
		end
		-- La última muestra de un tramo es la primera del siguiente: se deshace el paso que sobra.
		x, z = samples[STEPS_PER_SEGMENT + 1].position.x, samples[STEPS_PER_SEGMENT + 1].position.z
		heading = samples[STEPS_PER_SEGMENT + 1].heading
		segments[offset + 1] = { index = firstIndex + offset, samples = samples }
	end
	return segments
end

-- Una ruta con la API de RoadPath que entrega los tramos ya armados, en orden. Pedir más de los que hay es un error.
function SyntheticRoad.createPath(segments: { RoadPath.Segment }): RoadPath.RoadPath
	local firstIndex = segments[1].index
	local firstLoaded = firstIndex
	local lastLoaded = firstIndex - 1

	return {
		generateNextSegment = function(): RoadPath.Segment
			local segment = segments[lastLoaded + 1 - firstIndex + 1]
			if segment == nil then
				error("the synthetic road has no more segments", 2)
			end
			lastLoaded += 1
			return segment
		end,
		releaseSegmentsBefore = function(index: number)
			firstLoaded = math.max(firstLoaded, math.min(index, lastLoaded + 1))
		end,
		getSegment = function(index: number): RoadPath.Segment?
			if index < firstLoaded or index > lastLoaded then
				return nil
			end
			return segments[index - firstIndex + 1]
		end,
		getLoadedRange = function(): (number, number)
			return firstLoaded, lastLoaded
		end,
	}
end

return SyntheticRoad
