--!strict
-- Las tablas de material y de ocupación que pide WriteVoxels, indexadas [x][y][z] desde 1. Se reutilizan entre chunks:
-- cuando cambia la altura se pasan filas de z de una pila a otra, así armar un chunk no deja tablas para el recolector.

export type VoxelTables = {
	-- Material de cada vóxel, como clave propia (nunca un Enum).
	materials: { { { string } } },
	-- Fracción del vóxel que ocupa el terreno, de 0 a 1.
	occupancy: { { { number } } },
	-- Deja cada columna de x con exactamente `count` capas en y.
	setLayerCount: (count: number) -> (),
	getLayerCount: () -> number,
}

local VoxelTablesModule = {}

function VoxelTablesModule.new(sizeX: number, sizeZ: number, emptyMaterial: string): VoxelTables
	local materials: { { { string } } } = {}
	local occupancy: { { { number } } } = {}
	local freeMaterialRows: { { string } } = {}
	local freeOccupancyRows: { { number } } = {}
	for x = 1, sizeX do
		materials[x], occupancy[x] = {}, {}
	end
	local layerCount = 0

	local function takeMaterialRow(): { string }
		return table.remove(freeMaterialRows) or table.create(sizeZ, emptyMaterial)
	end

	local function takeOccupancyRow(): { number }
		return table.remove(freeOccupancyRows) or table.create(sizeZ, 0)
	end

	local function setLayerCount(count: number)
		for x = 1, sizeX do
			local materialLayers, occupancyLayers = materials[x], occupancy[x]
			while #materialLayers > count do
				table.insert(freeMaterialRows, table.remove(materialLayers) :: { string })
				table.insert(freeOccupancyRows, table.remove(occupancyLayers) :: { number })
			end
			while #materialLayers < count do
				table.insert(materialLayers, takeMaterialRow())
				table.insert(occupancyLayers, takeOccupancyRow())
			end
		end
		layerCount = count
	end

	local function getLayerCount(): number
		return layerCount
	end

	return {
		materials = materials,
		occupancy = occupancy,
		setLayerCount = setLayerCount,
		getLayerCount = getLayerCount,
	}
end

return VoxelTablesModule
