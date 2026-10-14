--!strict
local Runner = require("./Runner")
local Clamp = require("../src/vehicle/core/Clamp")
local Steering = require("../src/vehicle/core/Steering")

Runner.eq(Clamp.clamp(5, 0, 1), 1, "clamp alto")
Runner.eq(Clamp.clamp(-5, 0, 1), 0, "clamp bajo")
Runner.eq(Clamp.clamp(0.5, 0, 1), 0.5, "clamp medio")
Runner.eq(Steering.angle(2, 30), 30, "steering saturado")
Runner.eq(Steering.angle(0.5, 30), 15, "steering medio")

if Runner.finish() > 0 then
	error("hay fallas")
end
