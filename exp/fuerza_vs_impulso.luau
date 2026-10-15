-- Experimento #32 (preg. 1): VectorForce vs ApplyImpulse. execute_luau en Play (Server).
-- Parte 4x4x4 con gravedad 0; a = 10 studs/s^2 (F = m*a). Se mide dv por frame / (a*dt_real) en PreSimulation.
-- cap = false | 60 | 30: espera activa en Heartbeat para fijar el FPS.
local RS=game:GetService("RunService")
local ws=workspace
local function trial(mode, cap, nframes)
	local oldG=ws.Gravity; ws.Gravity=0
	local p=Instance.new("Part"); p.Size=Vector3.new(4,4,4); p.Position=Vector3.new(0,200,0); p.Anchored=false; p.Name="ExpP1"; p.Parent=ws
	local m=p.AssemblyMass
	local a=10
	local F=m*a
	local att=Instance.new("Attachment",p)
	if mode=="vf" then local vf=Instance.new("VectorForce"); vf.Attachment0=att; vf.RelativeTo=Enum.ActuatorRelativeTo.World; vf.ApplyAtCenterOfMass=true; vf.Force=Vector3.new(F,0,0); vf.Parent=p end
	local conns={}
	if cap then
		local prev=os.clock()
		table.insert(conns,RS.Heartbeat:Connect(function()
			local target=prev+1/cap
			local now=os.clock()
			while os.clock()<target do end
			prev=math.max(now,target)
		end))
	end
	local rec={}
	local lastT,lastV
	local count=0
	local fin=false
	table.insert(conns,RS.PreSimulation:Connect(function(dtArg)
		local t=os.clock()
		local v=p.AssemblyLinearVelocity.X
		if lastT then table.insert(rec,{dv=v-lastV,dt=t-lastT,dtArg=dtArg}) end
		lastT,lastV=t,v
		count+=1
		if mode=="imp" then p:ApplyImpulse(Vector3.new(F*dtArg,0,0)) end
		if count>=nframes then fin=true end
	end))
	while not fin do task.wait() end
	for _,c in conns do c:Disconnect() end
	p:Destroy(); ws.Gravity=oldG
	local sumR,minR,maxR,n,sdt,sdtArg=0,1e9,-1e9,0,0,0
	for i=6,#rec do
		local r=rec[i]
		local ratio=r.dv/(a*r.dt)
		sumR+=ratio; minR=math.min(minR,ratio); maxR=math.max(maxR,ratio); n+=1; sdt+=r.dt; sdtArg+=r.dtArg
	end
	return string.format("%s cap=%s: FPS=%.1f dtArg=%.4f ratio mean=%.3f min=%.3f max=%.3f mass=%.1f n=%d",mode,tostring(cap),n/sdt,sdtArg/n,sumR/n,minR,maxR,m,n)
end
local out={}
for _,cap in {false,60,30} do
	for _,mode in {"vf","imp"} do
		table.insert(out,trial(mode,cap,180))
	end
end
return table.concat(out,"\n")
