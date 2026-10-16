--!nocheck
-- Corrige un auto importado de Blockbench. NO es parte del juego: se pega en la barra de comandos de Studio
-- (Ver > Barra de comandos) con el modelo importado seleccionado, y crea una copia corregida al lado.
--
-- La regla (medida con el 147, ver docs/guia-de-desarrollo.md): el importador arma cada pieza con un Motor6D y Studio la
-- deja en `raíz · C0 · C1⁻¹`, pero la posición correcta es `raíz · (2·C0 − C1)`, porque el importador resta el pivote en
-- vez de sumarlo. Las submallas de un grupo (con C1 = 0) van en `centroDelGrupo + C0 − (C0_grupo − C1_grupo)`.
-- Las piezas sin Motor6D (sin grupo) no se tocan y se avisan.
local Selection = game:GetService("Selection")

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

local selected = Selection:Get()[1]
assert(selected ~= nil and selected:IsA("Model"), "Seleccioná el modelo importado (un Model).")

local copy = selected:Clone()
copy.Name = selected.Name .. "_corregido"
local root = findRoot(copy)
assert(root ~= nil, "No encontré la pieza raíz (la que no cuelga de ningún Motor6D).")

local corrected: { [BasePart]: Vector3 } = { [root] = root.Position }
local withoutGroup = {}

-- Primero las piezas que cuelgan de la raíz, después las submallas de cada grupo.
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
		elseif corrected[piece] == nil and motor.Part0 == root then
			corrected[piece] = root.Position + root.CFrame:VectorToWorldSpace(motor.C0.Position * 2 - motor.C1.Position)
		elseif corrected[piece] == nil and corrected[motor.Part0] ~= nil then
			local group = motorOf(copy, motor.Part0)
			if group ~= nil then
				local groupOffset = group.C0.Position - group.C1.Position
				corrected[piece] = corrected[motor.Part0]
					+ root.CFrame:VectorToWorldSpace(motor.C0.Position - groupOffset)
			end
		end
	end
end

for piece, position in corrected do
	if piece ~= root then
		piece.CFrame = CFrame.new(position) * piece.CFrame.Rotation
		local motor = motorOf(copy, piece)
		if motor ~= nil then
			motor:Destroy()
		end
	end
end

copy.Parent = selected.Parent
Selection:Set({ copy })
if #withoutGroup > 0 then
	warn("Piezas sin grupo (no se tocaron): " .. table.concat(withoutGroup, ", "))
end
print("Listo: " .. copy.Name .. " con " .. #pending .. " piezas revisadas y la raíz '" .. root.Name .. "'.")
