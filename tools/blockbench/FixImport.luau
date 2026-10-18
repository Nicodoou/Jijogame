--!nocheck
-- Corrige un auto importado de Blockbench. NO es parte del juego: se pega en la barra de comandos de Studio
-- (Ver > Barra de comandos) con el modelo importado seleccionado, y crea una copia corregida al lado.
--
-- Hay dos formatos de import y la herramienta detecta cuál es (si hay Motor6D o no):
--
-- 1. Rig (importer viejo, medido con el 147): cada pieza cuelga de un Motor6D y Studio la deja en `raíz · C0 · C1⁻¹`,
--    pero la posición correcta es `raíz · (2·C0 − C1)`, porque el importador resta el pivote en vez de sumarlo. Las
--    submallas de un grupo (con C1 = 0) van en `centroDelGrupo + C0 − (C0_grupo − C1_grupo)`.
-- 2. Nodos (importer nuevo, medido con el 147 mejorado): Model por grupo > Model `meshN_Node` > MeshPart, sin Motor6D.
--    Las piezas ya vienen en su lugar. Se aplanan: cada MeshPart pasa a colgar del modelo con el nombre de su grupo
--    (las submallas, con sufijo 2, 3...), igual que el 147 anterior, ancladas y con el pivote al pie del auto.
--
-- Las piezas sin grupo no se tocan y se avisan.
local Selection = game:GetService("Selection")

-- El 147 anterior tenía el pivote 1,22 studs debajo de la parte más baja del auto (el piso de Blockbench).
local PIVOT_BELOW_LOWEST_STUDS = 1.22

local function findRoot(model: Model): BasePart?
	local isPiece: { [Instance]: boolean } = {}
	for _, motor in model:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Part1 ~= nil then
			isPiece[motor.Part1] = true
		end
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not isPiece[part] then
			return part
		end
	end
	return nil
end

local function motorOf(model: Model, piece: BasePart): Motor6D?
	for _, motor in model:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Part1 == piece then
			return motor
		end
	end
	return nil
end

-- Posición corregida de una pieza del rig, o nil si todavía no se puede calcular (su grupo aún no está corregido).
local function correctedPosition(copy: Model, root: BasePart, corrected, motor: Motor6D): Vector3?
	if motor.Part0 == root then
		return root.Position + root.CFrame:VectorToWorldSpace(motor.C0.Position * 2 - motor.C1.Position)
	end
	local group = if corrected[motor.Part0] ~= nil then motorOf(copy, motor.Part0) else nil
	if group == nil then
		return nil
	end
	local groupOffset = group.C0.Position - group.C1.Position
	return corrected[motor.Part0] + root.CFrame:VectorToWorldSpace(motor.C0.Position - groupOffset)
end

local function fixRig(copy: Model, withoutGroup: { string }): number
	local root = findRoot(copy)
	assert(root ~= nil, "No encontré la pieza raíz (la que no cuelga de ningún Motor6D).")
	local corrected: { [BasePart]: Vector3 } = { [root] = root.Position }
	local pending = {}
	for _, part in copy:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			table.insert(pending, part)
		end
	end
	for _ = 1, #pending do
		for _, piece in pending do
			local motor = motorOf(copy, piece)
			if motor == nil then
				if not table.find(withoutGroup, piece.Name) then
					table.insert(withoutGroup, piece.Name)
				end
			elseif corrected[piece] == nil then
				corrected[piece] = correctedPosition(copy, root, corrected, motor)
			end
		end
	end
	for piece, position in corrected do
		if piece ~= root then
			piece.CFrame = CFrame.new(position) * piece.CFrame.Rotation
			motorOf(copy, piece):Destroy()
		end
	end
	return #pending
end

-- Número al final del nombre (mesh12_Node -> 12; "mesh" sin número -> 0), para ordenar las submallas como en Blockbench.
local function meshNumber(part: BasePart): number
	return tonumber(string.match(part.Parent.Name, "(%d+)_Node$")) or 0
end

local function flattenGroup(copy: Model, group: Model)
	local meshes = {}
	for _, descendant in group:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(meshes, descendant)
		end
	end
	table.sort(meshes, function(a, b)
		return meshNumber(a) < meshNumber(b)
	end)
	for index, mesh in meshes do
		mesh.Name = if index == 1 then group.Name else group.Name .. index
		mesh.Anchored = true
		mesh.Parent = copy
	end
	group:Destroy()
end

-- Avisa las piezas idénticas (misma posición y tamaño): suelen ser una malla puesta en el grupo equivocado.
local function warnDuplicates(copy: Model)
	local seen = {}
	for _, part in copy:GetChildren() do
		if part:IsA("BasePart") then
			local key = string.format(
				"%.2f,%.2f,%.2f|%.2f,%.2f,%.2f",
				part.Position.X,
				part.Position.Y,
				part.Position.Z,
				part.Size.X,
				part.Size.Y,
				part.Size.Z
			)
			if seen[key] ~= nil then
				warn("Piezas idénticas (posible malla en el grupo equivocado): " .. seen[key] .. " y " .. part.Name)
			end
			seen[key] = part.Name
		end
	end
end

local function fixNodes(copy: Model, withoutGroup: { string }): number
	local count = 0
	for _, child in copy:GetChildren() do
		if child:IsA("Model") then
			count += #child:GetDescendants()
			flattenGroup(copy, child)
		elseif child:IsA("BasePart") then
			table.insert(withoutGroup, child.Name)
		end
	end
	warnDuplicates(copy)
	return count
end

-- Pivote al centro del auto en x y z, y PIVOT_BELOW_LOWEST_STUDS debajo de lo más bajo; el modelo sigue mirando a +z.
local function placePivot(copy: Model)
	local box, size = copy:GetBoundingBox()
	copy.WorldPivot = CFrame.new(box.Position.X, box.Position.Y - size.Y / 2 - PIVOT_BELOW_LOWEST_STUDS, box.Position.Z)
end

local selected = Selection:Get()[1]
assert(selected ~= nil and selected:IsA("Model"), "Seleccioná el modelo importado (un Model).")

local copy = selected:Clone()
copy.Name = selected.Name .. "_corregido"
local withoutGroup = {}
local hasRig = copy:FindFirstChildWhichIsA("Motor6D", true) ~= nil
local reviewed = if hasRig then fixRig(copy, withoutGroup) else fixNodes(copy, withoutGroup)
if not hasRig then
	placePivot(copy)
end
copy.Parent = selected.Parent
Selection:Set({ copy })
if #withoutGroup > 0 then
	warn("Piezas sin grupo (no se tocaron): " .. table.concat(withoutGroup, ", "))
end
print(
	"Listo: "
		.. copy.Name
		.. " ("
		.. (if hasRig then "rig" else "nodos")
		.. ") con "
		.. reviewed
		.. " elementos revisados."
)
