--!nonstrict
-- EXPERIMENTO DESCARTABLE (exp/manejo). Adaptadores mínimos: input, simulador, ruedas, cámara y HUD.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local VehicleConfig = require(ReplicatedStorage.vehicle.core.VehicleConfig)
local VehicleSimulator = require(ReplicatedStorage.vehicle.core.VehicleSimulator)
local InputSmoother = require(ReplicatedStorage.input.core.InputSmoother)
local ChaseCamera = require(ReplicatedStorage.camera.core.ChaseCamera)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local WAKE_IMPULSE = Vector3.new(0, 0.001, 0)
local RAY_START_ABOVE = 3
local RAY_EXTRA = 1
local K = Enum.KeyCode
local wheelCount = #VehicleConfig.WHEELS

local function toV(v: Vector3)
	return vector.create(v.X, v.Y, v.Z)
end
local function toV3(v)
	return Vector3.new(v.x, v.y, v.z)
end

-- HUD de depuración.
local gui = Instance.new("ScreenGui")
gui.Name = "ExpHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local label = Instance.new("TextLabel")
label.Name = "Info"
label.Size = UDim2.fromOffset(360, 130)
label.Position = UDim2.fromOffset(10, 10)
label.BackgroundTransparency = 0.4
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.TextColor3 = Color3.new(1, 1, 1)
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.Font = Enum.Font.Code
label.TextSize = 18
label.Text = "esperando auto"
label.Parent = gui

-- Limitador de FPS para pruebas (atributo ExpFpsCap en Workspace): espera activa.
RunService.Heartbeat:Connect(function()
	local cap = workspace:GetAttribute("ExpFpsCap")
	if cap then
		local t0 = os.clock()
		local frame = 1 / cap
		while os.clock() - t0 < frame - 0.004 do
		end
	end
end)

local model = nil
while not model do
	model = workspace:FindFirstChild("Vehicle_" .. player.UserId)
	if not model then
		workspace.ChildAdded:Wait()
	end
end
local body = model:WaitForChild("Body")
local forces, motors = {}, {}
local mounts = {}
for i, w in VehicleConfig.WHEELS do
	mounts[i] = Vector3.new(w.offset.x, w.offset.y, w.offset.z)
	forces[i] = body:WaitForChild("Force" .. w.name)
	motors[i] = model:WaitForChild("Wheel" .. w.name):WaitForChild("Motor" .. w.name)
end
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { model }

local remote = ReplicatedStorage:WaitForChild("VehicleReleaseRequest")
local released = false
local cfg = table.clone(VehicleConfig)
local function rebuildCfg()
	cfg = table.clone(VehicleConfig)
	for k, v in workspace:GetAttributes() do
		if string.sub(k, 1, 4) == "Cfg_" then
			cfg[string.sub(k, 5)] = v
		end
	end
	table.freeze(cfg)
end
rebuildCfg()
workspace.AttributeChanged:Connect(function(k)
	if string.sub(k, 1, 4) == "Cfg_" then
		rebuildCfg()
	end
end)
local simState = VehicleSimulator.newState()
local inputState = InputSmoother.newState()
local feedback = nil
local spin = table.create(wheelCount, 0)
local steerVis = table.create(wheelCount, 0)
local compVis = table.create(wheelCount, 0)
local camState = nil
local lookingBack = false
local settleFrames = 0

local function readInput()
	if workspace:GetAttribute("ExpOv") then
		return {
			isSteerLeftDown = false, isSteerRightDown = false, isThrottleDown = false, isBrakeDown = false,
			isHandbrakeDown = workspace:GetAttribute("ExpHB") == true,
			isLookBackDown = false,
			gamepadSteer = workspace:GetAttribute("ExpSteer") or 0,
			gamepadThrottle = workspace:GetAttribute("ExpThr") or 0,
			gamepadBrake = workspace:GetAttribute("ExpBrk") or 0,
		}
	end
	local stick, r2, l2 = 0, 0, 0
	local handbrakePad, lookPad = false, false
	for _, st in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if st.KeyCode == Enum.KeyCode.Thumbstick1 then
			stick = st.Position.X
		elseif st.KeyCode == Enum.KeyCode.ButtonR2 then
			r2 = st.Position.Z
		elseif st.KeyCode == Enum.KeyCode.ButtonL2 then
			l2 = st.Position.Z
		elseif st.KeyCode == Enum.KeyCode.ButtonX then
			handbrakePad = st.Position.Z > 0.5
		elseif st.KeyCode == Enum.KeyCode.ButtonY then
			lookPad = st.Position.Z > 0.5
		end
	end
	local U = UserInputService
	return {
		isSteerLeftDown = U:IsKeyDown(K.A) or U:IsKeyDown(K.Left),
		isSteerRightDown = U:IsKeyDown(K.D) or U:IsKeyDown(K.Right),
		isThrottleDown = U:IsKeyDown(K.W) or U:IsKeyDown(K.Up),
		isBrakeDown = U:IsKeyDown(K.S) or U:IsKeyDown(K.Down),
		isHandbrakeDown = U:IsKeyDown(K.Space) or handbrakePad,
		isLookBackDown = U:IsKeyDown(K.C) or lookPad,
		gamepadSteer = stick,
		gamepadThrottle = r2,
		gamepadBrake = l2,
	}
end

local function step(dt)
	if body.Anchored then
		settleFrames += 1
		if not released and settleFrames > 20 then
			released = true
			remote:FireServer()
		end
		return
	end
	local cf = body.CFrame
	local up = cf.UpVector
	local rayLen = RAY_START_ABOVE
		+ VehicleConfig.SUSPENSION_REST_LENGTH_STUDS
		+ VehicleConfig.WHEEL_RADIUS_STUDS
		+ RAY_EXTRA
	local contacts = {}
	for i = 1, wheelCount do
		local mountPos = cf:PointToWorldSpace(mounts[i])
		local hit = workspace:Raycast(mountPos + up * RAY_START_ABOVE, -up * rayLen, rayParams)
		if hit then
			contacts[i] = {
				hasHit = true,
				distanceStuds = hit.Distance - RAY_START_ABOVE,
				point = toV(hit.Position),
				surface = "Road",
			}
		else
			contacts[i] = { hasHit = false, distanceStuds = 0, point = toV(mountPos), surface = nil }
		end
	end
	local chassis = {
		position = toV(body.AssemblyCenterOfMass),
		right = toV(cf.RightVector),
		up = toV(up),
		forward = toV(cf.LookVector),
		linearVelocity = toV(body.AssemblyLinearVelocity),
		angularVelocity = toV(body.AssemblyAngularVelocity),
		mass = body.AssemblyMass,
		gravity = workspace.Gravity,
	}
	local controls = {
		steer = inputState.steer,
		throttle = inputState.throttle,
		brake = inputState.brake,
		isHandbrakeOn = inputState.isHandbrakeOn,
	}
	local outputs
	simState, outputs, feedback = VehicleSimulator.step(simState, controls, chassis, contacts, dt, cfg)
	for i = 1, wheelCount do
		local o = outputs[i]
		forces[i].Force = toV3(o.force)
		compVis[i] = o.compressionStuds
		steerVis[i] = o.steerAngleRadians
		spin[i] += o.spinRadiansPerSecond * dt
	end
	body:ApplyImpulse(WAKE_IMPULSE)
end

local function updateWheels()
	for i = 1, wheelCount do
		local drop = VehicleConfig.SUSPENSION_REST_LENGTH_STUDS - compVis[i]
		local steer = if VehicleConfig.WHEELS[i].isFront then -steerVis[i] else 0
		motors[i].Transform = CFrame.new(0, -drop, 0) * CFrame.Angles(0, steer, 0) * CFrame.Angles(spin[i], 0, 0)
	end
end

RunService.PreSimulation:Connect(function(dt)
	inputState = InputSmoother.step(inputState, readInput(), dt)
	lookingBack = inputState.isLookingBack
	step(dt)
	if feedback then
		label.Text = string.format(
			"vel %.1f st/s (fwd %.1f)\nmarcha %d  rpm %d\ndrift %.1f deg\nthr %.2f brk %.2f hb %s\ny %.2f  z %.1f",
			feedback.speedStudsPerSecond,
			feedback.forwardSpeedStudsPerSecond,
			feedback.gear,
			feedback.engineRpm,
			math.deg(feedback.driftAngleRadians),
			inputState.throttle,
			inputState.brake,
			tostring(inputState.isHandbrakeOn),
			body.Position.Y,
			body.Position.Z
		)
	end
end)

RunService.PreRender:Connect(function(dt)
	if not released then
		return
	end
	updateWheels()
	local cf = body.CFrame
	local view = {
		position = toV(body.Position),
		forward = toV(cf.LookVector),
		linearVelocity = toV(body.AssemblyLinearVelocity),
	}
	if not camState then
		camState = ChaseCamera.newState(view)
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local pose
	camState, pose = ChaseCamera.step(camState, view, lookingBack, dt)
	camera.CFrame = CFrame.lookAt(toV3(pose.position), toV3(pose.lookAt))
end)
