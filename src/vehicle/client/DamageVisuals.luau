--!strict
-- Lo que se ve del daño (WP-18, decisión P1): cuando una pieza se cae, oculta sus mallas en este cliente y suelta una
-- copia sin soldadura. No toca las soldaduras ni el dueño de red del auto. La copia no choca con nada durante
-- `GHOST_SECONDS`, nunca choca con el auto, y se borra a los `LIFETIME_SECONDS` o cuando sobran.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DamageConfig = require(ReplicatedStorage.vehicle.core.damage.DamageConfig)
local DamageTypes = require(ReplicatedStorage.vehicle.core.damage.DamageTypes)
local DebrisPolicy = require(ReplicatedStorage.vehicle.core.damage.DebrisPolicy)
local VehicleModels = require(ReplicatedStorage.vehicle.core.VehicleModels)
local VehicleParts = require(ReplicatedStorage.vehicle.shared.VehicleParts)

type DamageEvent = DamageTypes.DamageEvent
type VehicleModelSheet = VehicleModels.VehicleModelSheet

type Debris = { part: BasePart, bornSeconds: number }

local DEBRIS = DamageConfig.DEBRIS
local DEBRIS_FOLDER_NAME = "DamageDebris"
local HIDDEN = 1

local DamageVisuals = {}
DamageVisuals.__index = DamageVisuals

export type DamageVisuals = typeof(setmetatable(
	{} :: {
		_vehicle: Model,
		_sheet: VehicleModelSheet,
		_folder: Folder,
		_debris: { Debris },
	},
	DamageVisuals
))

function DamageVisuals.new(vehicle: Model, sheet: VehicleModelSheet): DamageVisuals
	local folder = Instance.new("Folder")
	folder.Name = DEBRIS_FOLDER_NAME
	folder.Parent = Workspace
	return setmetatable({ _vehicle = vehicle, _sheet = sheet, _folder = folder, _debris = {} }, DamageVisuals)
end

-- Las mallas visuales de la pieza, por el nombre que da la ficha.
local function meshesOf(self: DamageVisuals, pieceId: string): { BasePart }
	local visual = self._vehicle:FindFirstChild(VehicleParts.VISUAL_MODEL_NAME)
	local meshes = {}
	local refs = self._sheet.damageMeshes[pieceId]
	if refs == nil then
		return meshes
	end
	for _, ref in refs do
		local mesh = if visual ~= nil
			then visual:FindFirstChild(if type(ref) == "string" then ref else ref.mesh)
			else nil
		if mesh ~= nil and mesh:IsA("BasePart") then
			table.insert(meshes, mesh)
		end
	end
	return meshes
end

-- Copia suelta de la malla, apartada del auto hacia afuera y con su velocidad; sin colisión los primeros instantes.
local function createDebris(mesh: BasePart, body: BasePart): BasePart
	local copy = mesh:Clone()
	for _, child in copy:GetChildren() do
		if child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end
	copy.Anchored = false
	copy.Massless = false
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.LocalTransparencyModifier = 0
	copy.CollisionGroup = VehicleParts.DEBRIS_COLLISION_GROUP
	local outward = (mesh.Position - body.AssemblyCenterOfMass).Unit
	copy.CFrame = mesh.CFrame + outward * DEBRIS.SEPARATION_STUDS
	copy.AssemblyLinearVelocity = body.AssemblyLinearVelocity
	local ignoreBody = Instance.new("NoCollisionConstraint")
	ignoreBody.Part0, ignoreBody.Part1 = copy, body
	ignoreBody.Parent = copy
	task.delay(DEBRIS.GHOST_SECONDS, function()
		copy.CanCollide = true
	end)
	return copy
end

local function detachPiece(self: DamageVisuals, pieceId: string, nowSeconds: number)
	local body = self._vehicle:FindFirstChild(VehicleParts.BODY_NAME)
	for _, mesh in meshesOf(self, pieceId) do
		if body ~= nil and body:IsA("BasePart") then
			local copy = createDebris(mesh, body)
			copy.Parent = self._folder
			table.insert(self._debris, { part = copy, bornSeconds = nowSeconds })
		end
		mesh.LocalTransparencyModifier = HIDDEN
	end
end

-- Punto de extensión de las texturas por estado (T1): hasta que haya texturas, un golpe no cambia la apariencia.
local function applyDamageTexture(_self: DamageVisuals, _event: DamageEvent) end

function DamageVisuals.handleEvent(self: DamageVisuals, event: DamageEvent, nowSeconds: number)
	if event.kind == "detached" then
		detachPiece(self, event.pieceId, nowSeconds)
	else
		applyDamageTexture(self, event)
	end
end

-- Borra las piezas sueltas que cumplieron su vida y las que sobran.
function DamageVisuals.step(self: DamageVisuals, nowSeconds: number)
	if #self._debris == 0 then
		return
	end
	local born = {}
	for index, debris in self._debris do
		born[index] = debris.bornSeconds
	end
	for _, index in DebrisPolicy.selectToRemove(born, nowSeconds) do
		self._debris[index].part:Destroy()
		table.remove(self._debris, index)
	end
end

function DamageVisuals.destroy(self: DamageVisuals)
	self._folder:Destroy()
	table.clear(self._debris)
end

return DamageVisuals
