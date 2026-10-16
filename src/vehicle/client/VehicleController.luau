--!strict
-- Conecta el auto de Roblox con el simulador: lee el chasis, lanza los rayos, aplica las fuerzas y mueve las ruedas.
-- Mientras el auto está anclado espera a que el mundo esté listo y le pide al servidor que lo suelte.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RoadPoint = require(ReplicatedStorage.shared.contracts.RoadPoint)
local Surface = require(ReplicatedStorage.shared.contracts.Surface)
local WorldReady = require(ReplicatedStorage.shared.contracts.WorldReady)
local VectorConversion = require(ReplicatedStorage.vehicle.shared.VectorConversion)
local VehicleParts = require(ReplicatedStorage.vehicle.shared.VehicleParts)
local VehicleTypes = require(ReplicatedStorage.vehicle.core.VehicleTypes)
local TuningOverrides = require("./TuningOverrides")
local VehicleRig = require("./VehicleRig")
local WheelRays = require("./WheelRays")
local WheelVisuals = require("./WheelVisuals")

type ChassisSample = VehicleTypes.ChassisSample
type VehicleControls = VehicleTypes.VehicleControls
type VehicleFeedback = VehicleTypes.VehicleFeedback
type VehicleSettings = VehicleTypes.VehicleSettings
type VehicleState = VehicleTypes.VehicleState

type WheelContact = VehicleTypes.WheelContact
type WheelOutput = VehicleTypes.WheelOutput

export type Simulator = {
	newState: (config: VehicleSettings?) -> VehicleState,
	step: (
		state: VehicleState,
		controls: VehicleControls,
		chassis: ChassisSample,
		contacts: { WheelContact? },
		dt: number,
		config: VehicleSettings?
	) -> (VehicleState, { WheelOutput }, VehicleFeedback),
}

export type Dependencies = {
	getSurfaceAt: Surface.GetSurfaceAt,
	isWorldReadyAt: WorldReady.IsWorldReadyAt,
	getSpawnPoint: RoadPoint.GetSpawnPoint,
	simulator: Simulator,
	config: VehicleSettings,
}

export type VehicleView = {
	position: vector,
	forward: vector,
	linearVelocity: vector,
}

type Session = {
	rig: VehicleRig.VehicleRig,
	visuals: WheelVisuals.WheelVisuals,
	rayParams: RaycastParams,
}

-- Sin un impulso mínimo por frame el chasis se duerme y la suspensión diverge (#32).
local WAKE_IMPULSE = Vector3.new(0, 0.001, 0)

local VehicleController = {}
VehicleController.__index = VehicleController

export type VehicleController = typeof(setmetatable(
	{} :: {
		_deps: Dependencies,
		_tuning: TuningOverrides.TuningOverrides,
		_remote: RemoteEvent?,
		_session: Session?,
		_state: VehicleState,
		_feedback: VehicleFeedback?,
		_hasRequestedRelease: boolean,
	},
	VehicleController
))

function VehicleController.new(deps: Dependencies): VehicleController
	return setmetatable({
		_deps = deps,
		_tuning = TuningOverrides.new(deps.config, Workspace, RunService:IsStudio()),
		_remote = nil,
		_session = nil,
		_state = deps.simulator.newState(deps.config),
		_feedback = nil,
		_hasRequestedRelease = false,
	}, VehicleController)
end

local function findSession(config: VehicleSettings): Session?
	local rig = VehicleRig.find(Players.LocalPlayer.UserId, config)
	if rig == nil then
		return nil
	end
	return { rig = rig, visuals = WheelVisuals.new(rig.motors), rayParams = WheelRays.newParams(rig.model) }
end

function VehicleController.start(self: VehicleController)
	self._remote = ReplicatedStorage:WaitForChild(VehicleParts.RELEASE_REMOTE_NAME) :: RemoteEvent
	self._session = findSession(self._tuning:getConfig())
end

function VehicleController.getVehiclePosition(self: VehicleController): vector
	local session = self._session
	if session == nil then
		return self._deps.getSpawnPoint().position
	end
	return VectorConversion.toVector(session.rig.body.Position)
end

function VehicleController.getVehicleView(self: VehicleController): VehicleView?
	local session = self._session
	if session == nil then
		return nil
	end
	local body = session.rig.body
	return {
		position = VectorConversion.toVector(body.Position),
		forward = VectorConversion.toVector(body.CFrame.LookVector),
		linearVelocity = VectorConversion.toVector(body.AssemblyLinearVelocity),
	}
end

function VehicleController.getFeedback(self: VehicleController): VehicleFeedback?
	return self._feedback
end

local function readChassis(body: BasePart): ChassisSample
	local cframe = body.CFrame
	return {
		origin = VectorConversion.toVector(body.Position),
		position = VectorConversion.toVector(body.AssemblyCenterOfMass),
		right = VectorConversion.toVector(cframe.RightVector),
		up = VectorConversion.toVector(cframe.UpVector),
		forward = VectorConversion.toVector(cframe.LookVector),
		linearVelocity = VectorConversion.toVector(body.AssemblyLinearVelocity),
		angularVelocity = VectorConversion.toVector(body.AssemblyAngularVelocity),
		mass = body.AssemblyMass,
		gravity = Workspace.Gravity,
	}
end

local function waitForWorld(self: VehicleController, body: BasePart)
	local remote = self._remote
	if self._hasRequestedRelease or remote == nil then
		return
	end
	if self._deps.isWorldReadyAt(VectorConversion.toVector(body.Position)) then
		self._hasRequestedRelease = true
		remote:FireServer()
	end
end

local function drive(self: VehicleController, session: Session, controls: VehicleControls, dt: number)
	local config = self._tuning:getConfig()
	local rig = session.rig
	local contacts = WheelRays.cast(rig.body.CFrame, rig.mounts, session.rayParams, self._deps.getSurfaceAt, config)
	local nextState, outputs, feedback =
		self._deps.simulator.step(self._state, controls, readChassis(rig.body), contacts, dt, config)
	self._state = nextState
	self._feedback = feedback
	for index, output in outputs do
		rig.forces[index].Force = VectorConversion.toVector3(output.force)
	end
	rig.body:ApplyImpulse(WAKE_IMPULSE)
	session.visuals:update(outputs, dt, config)
end

-- Corre en PreSimulation. Si el auto todavía no llegó al cliente, vuelve a buscarlo en el frame siguiente.
function VehicleController.step(self: VehicleController, controls: VehicleControls, dt: number)
	self._session = self._session or findSession(self._tuning:getConfig())
	local session = self._session
	if session == nil then
		return
	end
	if session.rig.body.Anchored then
		waitForWorld(self, session.rig.body)
	else
		drive(self, session, controls, dt)
	end
end

return VehicleController
