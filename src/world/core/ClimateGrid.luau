--!strict
-- Grilla de muestras de clima con interpolación bilineal de los parámetros (relieve, humedad y temperatura).
-- Se interpolan los parámetros y no los pesos de bioma: así no quedan pliegues dentro de la grilla.

local BiomeTypes = require("./BiomeTypes")

export type ClimateSample = BiomeTypes.ClimateSample

export type ClimateGrid = {
	originX: number,
	originZ: number,
	stepStuds: number,
	columnCount: number,
	rowCount: number,
	-- Clima interpolado en una posición; fuera de la grilla vale lo del borde más cercano.
	sampleAt: (x: number, z: number) -> ClimateSample,
}

local MIN_NODES_PER_AXIS = 2

local function lerp(from: number, to: number, fraction: number): number
	return from + (to - from) * fraction
end

-- Índice de la celda y fracción dentro de ella para una coordenada medida en pasos desde el origen.
local function locateCell(coordinateInSteps: number, nodeCount: number): (number, number)
	local clamped = math.clamp(coordinateInSteps, 0, nodeCount - 1)
	local cell = math.min(math.floor(clamped), nodeCount - MIN_NODES_PER_AXIS)
	return cell, clamped - cell
end

local ClimateGrid = {}

-- `samples` va por filas: el nodo (columna, fila) con base 0 está en samples[fila * columnCount + columna + 1].
function ClimateGrid.new(
	originX: number,
	originZ: number,
	stepStuds: number,
	columnCount: number,
	rowCount: number,
	samples: { ClimateSample }
): ClimateGrid
	if columnCount < MIN_NODES_PER_AXIS or rowCount < MIN_NODES_PER_AXIS then
		error("a grid needs at least two nodes per axis", 2)
	end
	if #samples ~= columnCount * rowCount then
		error("the grid needs one sample per node", 2)
	end

	local function sampleAt(x: number, z: number): ClimateSample
		local column, columnFraction = locateCell((x - originX) / stepStuds, columnCount)
		local row, rowFraction = locateCell((z - originZ) / stepStuds, rowCount)
		local base = row * columnCount + column + 1
		local lowLeft, lowRight = samples[base], samples[base + 1]
		local highLeft, highRight = samples[base + columnCount], samples[base + columnCount + 1]
		local function blend(field: "relief" | "humidity" | "temperature"): number
			local low = lerp(lowLeft[field], lowRight[field], columnFraction)
			local high = lerp(highLeft[field], highRight[field], columnFraction)
			return lerp(low, high, rowFraction)
		end
		return { relief = blend("relief"), humidity = blend("humidity"), temperature = blend("temperature") }
	end

	return {
		originX = originX,
		originZ = originZ,
		stepStuds = stepStuds,
		columnCount = columnCount,
		rowCount = rowCount,
		sampleAt = sampleAt,
	}
end

return ClimateGrid
