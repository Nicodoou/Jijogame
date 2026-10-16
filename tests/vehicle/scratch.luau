--!strict
local ToyWorld = require("./ToyWorld")
local idle = { steer = 0, throttle = 0, brake = 0, isHandbrakeOn = false }
for _, case in { { 0.15, 0.3, 0.1 }, { -0.15, -0.3, 0 }, { 0, 0, 0.2 } } do
	for _, fps in { 30, 60 } do
		local r = ToyWorld.new({
			frameSeconds = 1 / fps,
			dropStuds = 0.5,
			centerOfMassOffset = vector.create(case[3], -case[2], -case[1]),
		})
		local p2 = r.world.position
		local md, ms, pitch, roll = 0, 0, 0, 0
		r.run(10, function()
			return idle
		end, function(w)
			if w.timeSeconds < 2 then
				p2 = w.position
				return
			end
			local d = w.position - p2
			md = math.max(md, math.sqrt(d.x * d.x + d.z * d.z))
			ms = math.max(ms, vector.magnitude(w.linearVelocity))
			pitch = math.max(pitch, math.abs(math.deg(math.asin(w.forward.y))))
			roll = math.max(roll, math.abs(math.deg(math.asin(w.right.y))))
		end)
		local o = r.world.outputs
		local f, b = o[1].force.y + o[2].force.y, o[3].force.y + o[4].force.y
		local l, rr = o[1].force.y + o[3].force.y, o[2].force.y + o[4].force.y
		print(
			fps,
			case[1],
			case[2],
			case[3],
			"drift",
			md,
			"speed",
			ms,
			"pitch",
			pitch,
			"roll",
			roll,
			"front/total",
			f / (f + b),
			"left/total",
			l / (l + rr)
		)
	end
end
