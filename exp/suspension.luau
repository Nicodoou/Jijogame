-- Experimento #32 (preg. 2 y 3): suspension por raycast. Se ejecuta con execute_luau en Play (Server).
-- Modos: "vf0" VectorForce puro, "vf" VectorForce + impulso minimo para despertar, "imp" ApplyImpulseAtPosition
-- Parametros al inicio (CONFIGS). Resultados: ServerStorage.ExpResults (StringValue), una linea por prueba.
local RS = game:GetService("RunService")
local SS = game:GetService("ServerStorage")
local ws = workspace

local CONFIGS = _EXP_CONFIGS or {} -- {freq, zeta, cap(fps|false), mode("vf"|"imp")}
local L0 = 4 -- largo de resorte extendido (studs), del punto de rueda al suelo
local OFFS = { Vector3.new(-2.5,-1,-4), Vector3.new(2.5,-1,-4), Vector3.new(-2.5,-1,4), Vector3.new(2.5,-1,4) }

local out = SS:FindFirstChild("ExpResults") or Instance.new("StringValue", SS)
out.Name = "ExpResults"
out.Value = ""

local function trial(freq, zeta, cap, mode, kind)
	local g = ws.Gravity
	local gy = ws:Raycast(Vector3.new(0,50,0), Vector3.new(0,-100,0)).Position.Y
	local c = Instance.new("Part")
	c.Size = Vector3.new(6,2,10); c.Name = "ExpChassis"; c.Anchored = true
	local m = c.Mass -- OJO: AssemblyMass da inf si esta anclada y parentada
	local w = 2*math.pi*freq
	local kw = (m/4)*w*w
	local cw = 2*zeta*math.sqrt(kw*(m/4))
	local xeq = g/(w*w)
	local yeq = gy + (L0 - xeq) + 1
	c.Position = Vector3.new(0, yeq + (kind=="drop" and 2 or 0), 0)
	c.Parent = ws
	local atts, vfs = {}, {}
	for i,o in OFFS do
		local a = Instance.new("Attachment"); a.Position = o; a.Parent = c; atts[i] = a
		if mode == "vf" or mode == "vf0" then
			local vf = Instance.new("VectorForce"); vf.Attachment0 = a; vf.RelativeTo = Enum.ActuatorRelativeTo.World
			vf.ApplyAtCenterOfMass = false; vf.Force = Vector3.zero; vf.Parent = c; vfs[i] = vf
		end
	end
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = {c}
	c.Anchored = false
	local conns = {}
	if cap then
		local prev = os.clock()
		table.insert(conns, RS.Heartbeat:Connect(function()
			local target = prev + 1/cap
			local now = os.clock()
			while os.clock() < target do end
			prev = math.max(now, target)
		end))
	end
	local ys, ts, cost, ncost = {}, {}, 0, 0
	local t0, fin, tapped = nil, false, false
	table.insert(conns, RS.PreSimulation:Connect(function(dt)
		local t = os.clock()
		t0 = t0 or t
		table.insert(ys, c.Position.Y); table.insert(ts, t - t0)
		if t - t0 >= 5 then fin = true end
		if kind == "tap" and not tapped and t - t0 >= 1 then tapped = true; c:ApplyImpulse(Vector3.new(0, m*2, 0)) end
		local s = os.clock()
		local cf = c.CFrame
		for i,o in OFFS do
			local pw = cf * o
			local res = ws:Raycast(pw + Vector3.new(0,2,0), Vector3.new(0,-(2+L0),0), rp)
			local F = 0
			if res then
				local d = res.Distance - 2
				local x = L0 - d
				if x > 0 then
					local vc = -c:GetVelocityAtPosition(pw).Y
					F = math.max(0, kw*x + cw*vc)
				end
			end
			if mode ~= "imp" then vfs[i].Force = Vector3.new(0,F,0)
			else c:ApplyImpulseAtPosition(Vector3.new(0,F*dt,0), pw) end
		end
		if mode == "vf" then c:ApplyImpulse(Vector3.new(0,0.001,0)) end -- despertar: sin esto el chasis "duerme" y la suspension diverge
		cost += os.clock() - s; ncost += 1
	end))
	while not fin do task.wait() end
	for _,cn in conns do cn:Disconnect() end
	c:Destroy()
	local n = #ys
	local fps = (n-1) / (ts[n] - ts[1])
	local mn, mx, ptp = 1e9, -1e9, 0
	local mnL, mxL = 1e9, -1e9
	local crossings, lastSign, lastBig = 0, 0, 0
	local diverged = false
	local sf, nf = 0, 0
	for i = 1, n do if ts[i] >= 4 then sf += ys[i]; nf += 1 end end
	for i = 1, n do
		local dev = ys[i] - yeq
		if dev ~= dev or math.abs(dev) > 50 then diverged = true end
		mn = math.min(mn, ys[i]); mx = math.max(mx, ys[i])
		if ts[i] >= 3 then mnL = math.min(mnL, ys[i]); mxL = math.max(mxL, ys[i]) end
		local sg = dev > 0.05 and 1 or (dev < -0.05 and -1 or 0)
		if sg ~= 0 then
			if lastSign ~= 0 and sg ~= lastSign then crossings += 1 end
			lastSign = sg; lastBig = ts[i]
		end
	end
	return string.format("%s f=%.1f z=%.1f fps=%.1f %s | m=%.1f yeq=%.2f ptp_total=%.4f ptp_ult2s=%.4f minDevAbajo=%.2f maxDevArriba=%.2f cruces=%d ultimo|dev|>0.05 en t=%.2fs diverge=%s finalDev=%.4f cost_us=%.1f",
		mode, freq, zeta, fps, kind, m, yeq, mx-mn, mxL-mnL, mn-yeq, mx-yeq, crossings, lastBig, tostring(diverged), sf/nf - yeq, cost/ncost*1e6)
end

task.spawn(function()
	for _,cfg in CONFIGS do
		for _,kind in (cfg[5] or {"rest","drop"}) do
			local ok, r = pcall(trial, cfg[1], cfg[2], cfg[3], cfg[4], kind)
			out.Value ..= (ok and r or ("ERR "..tostring(r))) .. "\n"
			task.wait(0.2)
		end
	end
	out.Value ..= "DONE\n"
end)
