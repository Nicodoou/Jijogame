--!nonstrict
-- EXPERIMENTO DESCARTABLE (exp/manejo). Crea el auto de cajas y lo suelta cuando el cliente avisa.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VehicleConfig = require(ReplicatedStorage.vehicle.core.VehicleConfig)

Players.CharacterAutoLoads = false

local SPAWN_HEIGHT = 4
local remote = Instance.new("RemoteEvent")
remote.Name = "VehicleReleaseRequest"
remote.Parent = ReplicatedStorage

local function part(name, size, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function spawnFor(player)
	local model = Instance.new("Model")
	model.Name = "Vehicle_" .. player.UserId
	model:SetAttribute("OwnerUserId", player.UserId)
	local body = part("Body", Vector3.new(6, 2, 10), Color3.fromRGB(150, 150, 150))
	body.Anchored = true
	body.CFrame = CFrame.lookAt(Vector3.new(0, SPAWN_HEIGHT, 0), Vector3.new(0, SPAWN_HEIGHT, -1))
	body.Parent = model
	model.PrimaryPart = body
	for _, w in VehicleConfig.WHEELS do
		local offset = Vector3.new(w.offset.x, w.offset.y, w.offset.z)
		local diameter = VehicleConfig.WHEEL_RADIUS_STUDS * 2
		local wheel = part("Wheel" .. w.name, Vector3.new(1.2, diameter, diameter), Color3.new(0.05, 0.05, 0.05))
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Massless = true
		wheel.CanCollide = false
		wheel.CanQuery = false
		wheel.CanTouch = false
		wheel.CFrame = body.CFrame * CFrame.new(offset)
		local motor = Instance.new("Motor6D")
		motor.Name = "Motor" .. w.name
		motor.Part0 = body
		motor.Part1 = wheel
		motor.C0 = CFrame.new(offset)
		motor.Parent = wheel
		wheel.Parent = model
		local att = Instance.new("Attachment")
		att.Name = "Mount" .. w.name
		att.Position = offset
		att.Parent = body
		local vf = Instance.new("VectorForce")
		vf.Name = "Force" .. w.name
		vf.Attachment0 = att
		vf.RelativeTo = Enum.ActuatorRelativeTo.World
		vf.ApplyAtCenterOfMass = false
		vf.Force = Vector3.zero
		vf.Parent = body
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = workspace
	player.ReplicationFocus = body
	return model
end

local released = {}
remote.OnServerEvent:Connect(function(player)
	if released[player] then
		return
	end
	local model = workspace:FindFirstChild("Vehicle_" .. player.UserId)
	local body = model and model:FindFirstChild("Body")
	if not body then
		return
	end
	released[player] = true
	body.Anchored = false
	body:SetNetworkOwner(player)
end)

Players.PlayerAdded:Connect(spawnFor)
for _, p in Players:GetPlayers() do
	task.spawn(spawnFor, p)
end
Players.PlayerRemoving:Connect(function(p)
	released[p] = nil
	local m = workspace:FindFirstChild("Vehicle_" .. p.UserId)
	if m then
		m:Destroy()
	end
end)
