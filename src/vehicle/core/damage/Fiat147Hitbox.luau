--!strict
-- Caja de cada malla del Fiat 147 (`Workspace.147_v2`, 44 mallas sin rotar): centro en el marco del modelo (origen en su
-- pivote, x a la izquierda, +z adelante) y tamaño. Son datos medidos, no se calculan en el juego porque leer mallas
-- ahí no está garantizado. Generado en Studio (Edit) con este script, 2026-10-18; al cambiar el modelo hay que volver
-- a correrlo y pegar el resultado:
--
--   local model = workspace["147_v2"]
--   local pivot = model:GetPivot()
--   local rx, ry, rz = pivot:ToOrientation()
--   assert(math.abs(rx) + math.abs(ry) + math.abs(rz) < 1e-3, "modelo rotado")
--   local meshes = {}
--   for _, part in model:GetDescendants() do
--   	if part:IsA("MeshPart") then
--   		assert(part.Orientation.Magnitude < 0.01, part.Name .. " rotada")
--   		table.insert(meshes, part)
--   	end
--   end
--   table.sort(meshes, function(a, b) return a.Name < b.Name end)
--   for _, part in meshes do
--   	local c, s = part.Position - pivot.Position, part.Size
--   	print(string.format('\t["%s"] = box(%.3f, %.3f, %.3f, %.3f, %.3f, %.3f),', part.Name, c.X, c.Y, c.Z, s.X, s.Y, s.Z))
--   end
local DamageTypes = require("./DamageTypes")

type MeshBox = DamageTypes.MeshBox

local function box(cx: number, cy: number, cz: number, sx: number, sy: number, sz: number): MeshBox
	return table.freeze({ center = vector.create(cx, cy, cz), size = vector.create(sx, sy, sz) })
end

local boxes: { [string]: MeshBox } = {
	["Baul"] = box(0.000, 4.466, -4.005, 4.253, 1.987, 1.663),
	["Capot"] = box(-1.279, 3.682, 3.640, 2.557, 0.424, 2.763),
	["Capot2"] = box(1.279, 3.682, 3.640, 2.557, 0.424, 2.763),
	["Chasis"] = box(0.000, 2.379, -4.498, 4.240, 0.199, 0.530),
	["Chasis10"] = box(-2.233, 2.744, 4.101, 0.464, 0.927, 1.298),
	["Chasis11"] = box(-1.888, 2.743, 3.054, 1.391, 0.928, 2.387),
	["Chasis12"] = box(1.291, 2.943, -2.978, 2.585, 1.855, 3.849),
	["Chasis13"] = box(-1.291, 2.943, -2.978, 2.585, 1.855, 3.849),
	["Chasis14"] = box(1.290, 3.738, 0.093, 2.588, 3.445, 9.871),
	["Chasis15"] = box(0.000, 2.413, 4.313, 4.240, 0.265, 0.132),
	["Chasis16"] = box(-1.290, 3.738, 0.093, 2.588, 3.445, 9.871),
	["Chasis2"] = box(0.000, 2.280, 0.007, 4.770, 0.530, 3.710),
	["Chasis3"] = box(0.000, 2.148, 3.120, 2.650, 0.265, 2.517),
	["Chasis4"] = box(0.000, 2.148, -3.306, 2.650, 0.265, 2.915),
	["Chasis5"] = box(1.888, 2.743, 3.054, 1.391, 0.928, 2.387),
	["Chasis6"] = box(1.888, 2.743, -3.041, 1.391, 0.928, 2.387),
	["Chasis7"] = box(-1.888, 2.743, -3.041, 1.391, 0.928, 2.387),
	["Chasis8"] = box(-1.789, 2.743, 3.054, 1.193, 0.928, 2.387),
	["Chasis9"] = box(2.233, 2.744, 4.101, 0.464, 0.927, 1.298),
	["FL Light"] = box(1.607, 2.916, 4.532, 1.044, 0.583, 0.422),
	["FR Light"] = box(-1.607, 2.916, 4.532, 1.044, 0.583, 0.422),
	["Front Bumper"] = box(0.000, 2.413, 4.541, 5.167, 0.397, 0.737),
	["Interior front"] = box(0.000, 2.997, -1.123, 4.240, 1.767, 6.235),
	["LF Wheel"] = box(2.021, 2.017, 3.054, 0.729, 1.593, 1.590),
	["LR Wheel"] = box(2.021, 2.017, -3.041, 0.729, 1.593, 1.590),
	["Left Door"] = box(2.153, 3.605, 0.338, 0.861, 3.180, 2.782),
	["Left Driver's seat"] = box(1.259, 3.506, -0.345, 1.590, 1.789, 1.895),
	["Left Mirror"] = box(2.485, 3.897, 1.689, 0.281, 0.281, 0.265),
	["Left Mirror2"] = box(2.782, 4.036, 1.623, 0.530, 0.331, 0.133),
	["Parrilla"] = box(0.000, 2.876, 4.611, 2.252, 0.662, 0.199),
	["RF Wheel"] = box(-2.021, 2.017, 3.054, 0.729, 1.593, 1.590),
	["RL Light"] = box(1.795, 2.916, -4.697, 1.206, 0.583, 0.397),
	["RR Light"] = box(-1.795, 2.916, -4.697, 1.206, 0.583, 0.397),
	["RR Wheel"] = box(-2.021, 2.017, -3.041, 0.729, 1.593, 1.590),
	["Rear Bumper"] = box(0.000, 2.413, -4.660, 5.167, 0.397, 0.737),
	["Rear Mirror"] = box(0.000, 4.831, 0.232, 0.795, 0.331, 0.133),
	["Rear seats"] = box(0.000, 3.174, -2.894, 4.505, 1.788, 2.568),
	["Right Door"] = box(-2.153, 3.605, 0.338, 0.861, 3.180, 2.782),
	["Right Driver's seat"] = box(-1.259, 3.506, -0.345, 1.590, 1.789, 1.895),
	["Right Mirror"] = box(-2.485, 3.897, 1.689, 0.281, 0.281, 0.265),
	["Right Mirror2"] = box(-2.783, 4.036, 1.623, 0.530, 0.331, 0.132),
	["Right Mirror3"] = box(0.000, 2.379, -4.498, 4.240, 0.199, 0.530),
	["Steering Wheel"] = box(1.259, 3.733, 1.120, 0.927, 0.788, 0.453),
	["Techo"] = box(0.000, 5.328, -1.451, 3.445, 0.265, 3.445),
}

return table.freeze(boxes)
