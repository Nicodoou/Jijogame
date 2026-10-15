DEBUGSTUCK = false
-- Prototipo descartable: guia grande + curvas locales.
local STEP = 2
local rad, deg = math.rad, math.deg
local PI = math.pi

local function wrap(a) return (a + PI) % (2*PI) - PI end

local BASE = {
  AREA = 8000, GUIDE_MARGIN = 2000, GUIDE_EDGE = 1000, GUIDE_PULL_RANGE = 1000,
  GUIDE_STEP = 1200, GUIDE_CLEARANCE = 900, GUIDE_MAX_TURN = rad(70),
  LOOKAHEAD = 600, LOCAL_DEV = 250, RECOVER = 1.6,
  NEIGH = 1200, CLEAR = 200, LOOK = 4000,
  BT_STEP = 6, MINR = 60, GUIDE_ALTS = {30, 60, 90, 120}, GUIDE_SEG_CHECK = true,
}

local kinds = {
  {name="straight", w=2},
  {name="gentle", w=4, l0=180,l1=420, r0=180,r1=400, ramp=0.3, lobes=1},
  {name="sharp", w=4, l0=80,l1=180, r0=60,r1=110, ramp=0.35, lobes=1},
  {name="s", w=4, l0=240,l1=480, r0=90,r1=200, ramp=0.3, lobes=2},
  {name="hairpin", w=2},
}

-- ===================== guia =====================
local function pointSegDist(px, pz, ax, az, bx, bz)
  local dx, dz = bx-ax, bz-az
  local t = math.clamp(((px-ax)*dx + (pz-az)*dz) / (dx*dx + dz*dz), 0, 1)
  local ex, ez = px - (ax + dx*t), pz - (az + dz*t)
  return math.sqrt(ex*ex + ez*ez)
end

local function segsCross(a, b, c, d)
  local function orient(p, q, r) return (q[1]-p[1])*(r[2]-p[2]) - (q[2]-p[2])*(r[1]-p[1]) end
  local o1, o2, o3, o4 = orient(a,b,c), orient(a,b,d), orient(c,d,a), orient(c,d,b)
  return (o1 > 0) ~= (o2 > 0) and (o3 > 0) ~= (o4 > 0)
end

local function segSegDist(a, b, c, d)
  if segsCross(a, b, c, d) then return 0 end
  return math.min(
    pointSegDist(a[1], a[2], c[1], c[2], d[1], d[2]),
    pointSegDist(b[1], b[2], c[1], c[2], d[1], d[2]),
    pointSegDist(c[1], c[2], a[1], a[2], b[1], b[2]),
    pointSegDist(d[1], d[2], a[1], a[2], b[1], b[2]))
end

local function genGuide(cfg, count)
  local pts = {{0,0}}
  local heads = {0}
  local K = math.ceil(cfg.LOOK / cfg.GUIDE_STEP) + 2
  local backtracks, maxPop, iterations = 0, 0, 0
  local failCount, bestLen = 0, 1
  local alts = {}
  for _, a in cfg.GUIDE_ALTS do table.insert(alts, rad(a)); table.insert(alts, -rad(a)) end
  while #pts < count + 1 do
    iterations += 1
    if iterations > count * 400 then return nil, backtracks, maxPop end
    local n = #pts
    if n > bestLen then bestLen = n; failCount = 0 end
    local last, g = pts[n], heads[n]
    local u = (math.random()*2 - 1) * cfg.GUIDE_MAX_TURN
    local r = math.sqrt(last[1]^2 + last[2]^2)
    local edge = cfg.AREA - cfg.GUIDE_MARGIN
    if r > edge then
      local psi = math.atan2(-last[2], -last[1])
      local desired = math.clamp(wrap(psi - g), -cfg.GUIDE_MAX_TURN, cfg.GUIDE_MAX_TURN)
      local w = math.clamp((r - edge) / cfg.GUIDE_PULL_RANGE, 0, 1)
      u = u + (desired - u) * w
    end
    local accepted = false
    local cands = {u}
    for _, a in alts do table.insert(cands, a) end
    for _, delta in cands do
      local nh = g + delta
      local nx, nz = last[1] + cfg.GUIDE_STEP*math.cos(nh), last[2] + cfg.GUIDE_STEP*math.sin(nh)
      if math.sqrt(nx*nx + nz*nz) <= cfg.AREA - cfg.GUIDE_EDGE then
        local ok = true
        local newPt = {nx, nz}
        for i = math.max(1, n - K + 1), n do
          local dx, dz = nx - pts[i][1], nz - pts[i][2]
          if dx*dx + dz*dz < cfg.GUIDE_CLEARANCE^2 then ok = false break end
        end
        if ok and cfg.GUIDE_SEG_CHECK then
          for i = math.max(1, n - K + 1), n - 2 do
            if segSegDist(last, newPt, pts[i], pts[i+1]) < cfg.GUIDE_CLEARANCE then ok = false break end
          end
        end
        if ok then
          table.insert(pts, newPt); table.insert(heads, nh)
          accepted = true; break
        end
      end
    end
    if not accepted then
      if n <= 1 then return nil, backtracks, maxPop end
      failCount += 1
      local pops = math.min(n - 1, 1 + failCount // 8)
      for _ = 1, pops do table.remove(pts); table.remove(heads) end
      backtracks += pops; maxPop = math.max(maxPop, pops)
    end
  end
  return pts, backtracks, maxPop
end

-- ===================== ruta =====================
local function curv(peak, lobeSteps, rampSteps, lobes, s)
  local li = math.min(s // lobeSteps, lobes - 1)
  local sl = s - li*lobeSteps
  local f = math.min(1, sl/rampSteps, (lobeSteps - sl)/rampSteps)
  return (li % 2 == 0 and 1 or -1) * peak * f
end

local CELLKEY = 100003
local function genRoute(cfg, guide, totalSteps, stats)
  local M = #guide - 1
  local GS = cfg.GUIDE_STEP
  local function project(x, z, j0)
    local bestAbs, bestD, bestU, bestK = math.huge, 0, 0, j0
    for k = math.max(1, j0 - 1), math.min(M, j0 + 2) do
      local a, b = guide[k], guide[k+1]
      local dx, dz = b[1]-a[1], b[2]-a[2]
      local px, pz = x - a[1], z - a[2]
      local t = math.clamp((px*dx + pz*dz) / (GS*GS), 0, 1)
      local ex, ez = px - dx*t, pz - dz*t
      local dist = math.sqrt(ex*ex + ez*ez)
      if dist < bestAbs then
        bestAbs = dist
        local cross = dx*pz - dz*px
        bestD = (cross >= 0) and dist or -dist
        bestU = (k-1)*GS + t*GS
        bestK = k
      end
    end
    return bestD, bestU, bestK
  end
  local function pointAt(u)
    local k = math.clamp(math.floor(u / GS) + 1, 1, M)
    local t = math.clamp((u - (k-1)*GS)/GS, 0, 1)
    local a, b = guide[k], guide[k+1]
    return a[1] + (b[1]-a[1])*t, a[2] + (b[2]-a[2])*t
  end

  local X, Z, S, H = {0}, {0}, {0}, {0}
  local cells = {}
  local oldest = 1
  local CS = cfg.CLEAR
  local function cellOf(v) return math.floor(v / CS) end
  local function key(cx, cz) return cx*CELLKEY + cz end
  local function insert(i)
    local k = key(cellOf(X[i]), cellOf(Z[i]))
    local c = cells[k]
    if not c then c = {head = 1, n = 0}; cells[k] = c end
    c.n += 1; c[c.n] = i
  end
  local function expire(sNow)
    while oldest < #X and sNow - S[oldest] > cfg.LOOK + 3500 do
      local k = key(cellOf(X[oldest]), cellOf(Z[oldest]))
      local c = cells[k]
      if c then
        c.head += 1
        if c.head > c.n then cells[k] = nil end
      end
      oldest += 1
    end
  end
  insert(1)
  local C2 = cfg.CLEAR^2
  local function isClear(px, pz, s)
    local cx, cz = cellOf(px), cellOf(pz)
    for ddx = -1, 1 do for ddz = -1, 1 do
      local c = cells[key(cx+ddx, cz+ddz)]
      if c then
        for q = c.head, c.n do
          local j = c[q]
          if s - S[j] > (cfg.NEIGH_PREVIEW or cfg.NEIGH) then
            local dx, dz = px - X[j], pz - Z[j]
            if dx*dx + dz*dz < C2 then return false end
          end
        end
      end
    end end
    return true
  end

  local AREA2 = cfg.AREA^2
  local x, z, h, s, j = 0, 0, 0, 0, 1
  -- recorre partes desde un estado; devuelve muestras o nil + motivo
  local gdirs = {}
  for k = 1, M do gdirs[k] = math.atan2(guide[k+1][2]-guide[k][2], guide[k+1][1]-guide[k][1]) end
  local function walk(parts, px, pz, ph, ps, exempt)
    local psiLimit = math.huge
    if cfg.PSI_MAX and not exempt then
      local _, _, k0 = project(px, pz, j)
      psiLimit = math.max(cfg.PSI_MAX, math.abs(wrap(ph - gdirs[k0])))
    end
    local pk = 0
    local out = {}
    for _, part in parts do
      local peak, ls, rs, lobes = part[1], part[2], part[3], part[4]
      for st = 1, ls*lobes do
        local nk = curv(peak, ls, rs, lobes, st)
        local nh = ph + 0.5*(pk + nk)*STEP
        local sh = 0.5*(ph + nh)
        px += STEP*math.cos(sh); pz += STEP*math.sin(sh); ph = nh; pk = nk; ps += STEP
        if px*px + pz*pz > AREA2 then return nil, "area" end
        local d, _, kk = project(px, pz, j)
        if psiLimit < math.huge and math.abs(wrap(ph - gdirs[kk])) > psiLimit then return nil, "psi" end
        if math.abs(d) > cfg.LOCAL_DEV then return nil, "dev" end
        if not isClear(px, pz, ps) then return nil, "clear" end
        out[#out+1] = {px, pz, ph, ps}
      end
    end
    return out
  end
  local function preview(parts, exempt)
    local out, why = walk(parts, x, z, h, s, exempt)
    if not out then return nil, why end
    local last = out[#out]
    -- salida de emergencia: desde el final tiene que caber un giro cerrado hacia la guia
    local _, uEnd = project(last[1], last[2], j)
    local tx, tz = pointAt(uEnd + cfg.LOOKAHEAD)
    local e = wrap(math.atan2(tz - last[2], tx - last[1]) - last[3])
    if math.abs(e) > rad(3) then
      local R = cfg.MINR
      local n = math.ceil(math.abs(e)*R/STEP)
      local ramp = math.max(1, math.floor(0.25*n + 0.5))
      local escape = walk({{(e > 0 and 1 or -1)/R, n + ramp, ramp, 1}}, last[1], last[2], last[3], last[4], true)
      if not escape then return nil, "escape" end
    end
    return out
  end

  local function mkPiece(kind, sign, shorten)
    if kind.name == "straight" then
      local L = math.random(120, 360)
      local ls = L // STEP
      if shorten then ls = ls // 2 end
      return {{0, ls, 1, 1}}
    elseif kind.name == "hairpin" then
      local t = rad(120) + math.random()*rad(60)
      local R = cfg.MINR + math.random()*cfg.MINR*0.4
      local nmin, nmax = math.ceil(t*cfg.MINR/STEP), math.floor(t*cfg.MINR*1.4/STEP)
      local n = math.clamp(math.floor(t*R/STEP + 0.5), nmin, nmax)
      local ramp = math.max(1, math.floor(0.25*n + 0.5))
      local ls = n + ramp
      local peak = t/(n*STEP)
      local gap = math.random(20, 60)
      return {{sign*peak, ls, ramp, 1}, {0, gap, 1, 1}, {-sign*peak, ls, ramp, 1}}
    else
      local L = math.random(kind.l0, kind.l1)
      local R = kind.r0 + math.random()*(kind.r1 - kind.r0)
      local ls = math.floor(L/kind.lobes/STEP + 0.5)
      if shorten then ls = math.max(4, ls // 2) end
      local ramp = math.min(math.max(1, math.floor(kind.ramp*ls + 0.5)), ls // 2)
      return {{sign/R, ls, ramp, kind.lobes}}
    end
  end

  local function pickKind(restrictTurning, allowHairpin)
    local pool, tw = {}, 0
    for _, k in kinds do
      local ok = true
      if restrictTurning and (k.name == "straight" or k.name == "s" or k.name == "hairpin") then ok = false end
      if k.name == "hairpin" and not allowHairpin then ok = false end
      if ok then table.insert(pool, k); tw += k.w end
    end
    local r = math.random()*tw
    for _, k in pool do r -= k.w; if r <= 0 then return k end end
    return pool[#pool]
  end

  local function commit(out)
    for _, p in out do
      X[#X+1], Z[#Z+1], H[#H+1], S[#S+1] = p[1], p[2], p[3], p[4]
      insert(#X)
    end
    x, z, h, s = out[#out][1], out[#out][2], out[#out][3], out[#out][4]
    local _, _, k = project(x, z, j)
    j = k
    expire(s)
  end

  stats.kinds = stats.kinds or {}
  local stack, failCount, bestS = {}, 0, 0
  local function rollback(count)
    for _ = 1, count do
      local e = table.remove(stack)
      for i = #X, e.len + 1, -1 do
        local k = key(cellOf(X[i]), cellOf(Z[i]))
        local c = cells[k]
        if c then
          c[c.n] = nil; c.n -= 1
          if c.n < c.head then cells[k] = nil end
        end
        X[i], Z[i], S[i], H[i] = nil, nil, nil, nil
      end
      x, z, h, s, j = e.x, e.z, e.h, e.s, e.j
    end
  end
  local iterations = 0
  while s < totalSteps*STEP do
    iterations += 1
    if iterations > totalSteps * 6 then return X, Z, S, H, false, "stuck" end
    local d, u = project(x, z, j)
    if u + cfg.LOOKAHEAD > M*GS then return X, Z, S, H, true end
    local tx, tz = pointAt(u + cfg.LOOKAHEAD)
    local e = wrap(math.atan2(tz - z, tx - x) - h)
    local ae = math.abs(e)
    local restrict = ae > rad(45)
    local kind = pickKind(restrict, math.abs(d) < cfg.LOCAL_DEV*0.8)
    local pull = math.clamp(ae / rad(40), 0, 1)
    local p = 0.5 + 0.45*pull
    if ae > rad(90) then p = 1 end
    if math.abs(d) > 0.6*cfg.LOCAL_DEV then p = math.max(p, 0.95) end
    local toward = (e >= 0) and 1 or -1
    local sign = (math.random() < p) and toward or -toward
    if kind.name == "hairpin" then
      -- el primer giro se aleja de la guia para volver con el segundo
      sign = (d > 0) and -1 or 1
    end
    local out, usedKind
    local attempt = 0
    local function try(parts, name)
      attempt += 1
      local o, why = preview(parts, name == "hairpin")
      if not o then stats.reasons = stats.reasons or {}; stats.reasons[why] = (stats.reasons[why] or 0) + 1 end
      if o then out = o; usedKind = name end
      return o ~= nil
    end
    local _ = try(mkPiece(kind, sign, false), kind.name)
      or (kind.name ~= "straight" and try(mkPiece(kind, -sign, false), kind.name))
      or try(mkPiece(kind, sign, true), kind.name)
      or try(mkPiece(kinds[3], toward, false), "sharp")
      or try({{0, 20, 1, 1}}, "straight")
    if not out then
      stats.lastResort = (stats.lastResort or 0) + 1
      for _, sg in {toward, -toward} do
        for _, len in {60, 40, 24, 12} do
          if try({{sg/cfg.MINR, len, math.max(1, len//4), 1}}, "sharp") then break end
        end
        if out then break end
      end
    end
    if not out then
      if cfg.DEBUG then
        local best, bestDs = math.huge, 0
        for q = 1, #X do if s - S[q] > cfg.NEIGH and s - S[q] <= cfg.LOOK then local dd = math.sqrt((x-X[q])^2 + (z-Z[q])^2); if dd < best then best = dd; bestDs = s - S[q] end end end
        local a, b = guide[j], guide[j+1]
        local gdir = math.atan2(b[2]-a[2], b[1]-a[1])
        local turnNext = j < M and deg(wrap(math.atan2(guide[j+2][2]-b[2], guide[j+2][1]-b[1]) - gdir)) or 0
        print(string.format("stuck x=%.0f z=%.0f h=%.0f d=%.0f e=%.0f u=%.0f frac=%.2f nearestOld=%.0f(ds=%.0f) guideTurnNext=%.0f hRelGuide=%.0f", x, z, deg(h), d, deg(e), u, (u - (j-1)*GS)/GS, best, bestDs, turnNext, deg(wrap(h-gdir))))
      end
      if cfg.BACKTRACK and #stack > 0 and (stats.rollbacks or 0) < 600 then
        failCount += 1
        local pops = math.min(#stack, 1 + failCount // cfg.BT_STEP)
        rollback(pops)
        stats.rollbacks = (stats.rollbacks or 0) + 1
        stats.pops = (stats.pops or 0) + pops
        stats.maxPops = math.max(stats.maxPops or 0, pops)
        continue
      end
      return X, Z, S, H, false, "stuck"
    end
    stats.attemptHist = stats.attemptHist or {}
    stats.attemptHist[attempt] = (stats.attemptHist[attempt] or 0) + 1
    stats.kinds[usedKind] = (stats.kinds[usedKind] or 0) + 1
    table.insert(stack, {len = #X, x = x, z = z, h = h, s = s, j = j})
    if #stack > 3 then table.remove(stack, 1) end
    commit(out)
    if s > bestS then bestS = s; failCount = 0 end
  end
  return X, Z, S, H, true
end

-- ===================== verificacion y metricas =====================
local function verify(cfg, X, Z, S)
  local CS = cfg.CLEAR
  local cells = {}
  local function cellOf(v) return math.floor(v / CS) end
  for i = 1, #X do
    local k = cellOf(X[i])*CELLKEY + cellOf(Z[i])
    local c = cells[k]; if not c then c = {}; cells[k] = c end
    c[#c+1] = i
  end
  local viol, minDist, maxR = 0, math.huge, 0
  for i = 1, #X, 2 do
    maxR = math.max(maxR, math.sqrt(X[i]^2 + Z[i]^2))
    local cx, cz = cellOf(X[i]), cellOf(Z[i])
    for ddx = -1, 1 do for ddz = -1, 1 do
      local c = cells[(cx+ddx)*CELLKEY + cz + ddz]
      if c then
        for _, q in c do
          local ds = S[i] - S[q]
          if ds > cfg.NEIGH and ds <= cfg.LOOK then
            local dd = math.sqrt((X[i]-X[q])^2 + (Z[i]-Z[q])^2)
            minDist = math.min(minDist, dd)
            if dd < CS then viol += 1 end
          end
        end
      end
    end end
  end
  return viol, minDist, maxR
end

local function rallyMetrics(H)
  local n = #H
  local win = 1000 -- 2000 studs
  local pre = {0}
  for i = 2, n do pre[i] = pre[i-1] + math.abs(H[i] - H[i-1]) end
  local total, netBig, cumBig, maxNet = 0, 0, 0, 0
  local i = 1
  while i + win <= n do
    total += 1
    local net = math.abs(H[i+win] - H[i])
    local cum = pre[i+win] - pre[i]
    maxNet = math.max(maxNet, net)
    if net > PI then netBig += 1 end
    if cum > PI then cumBig += 1 end
    i += 100
  end
  local quads = {}
  for k = 1, n, 10 do
    quads[math.floor(((H[k] % (2*PI)) / (PI/2))) % 4] = true
  end
  local nq = 0 for _ in quads do nq += 1 end
  return total, netBig, cumBig, maxNet, nq
end

local function runConfig(label, over, seeds, segments)
  local cfg = table.clone(BASE)
  for k, v in over do cfg[k] = v end
  local guideCount = math.ceil(segments*256 / cfg.GUIDE_STEP * 1.4) + 6
  local agg = {guideFail=0, routeStuck=0, routeShort=0, backtracks=0, maxDepth=0, viol=0, violSeeds=0, minDist=math.huge,
    maxR=0, lastResort=0, windows=0, netBig=0, cumBig=0, seedsNet180=0, seedsQuad4=0, sharp=0, hair=0, km=0, time=0,
    attempts={}, maxNet=0, pieces=0, rollbacks=0, pops=0, maxPops=0}
  for seed = 1, seeds do
    math.randomseed(seed)
    local t0 = os.clock()
    local guide, bt, md = genGuide(cfg, guideCount)
    agg.backtracks += bt; agg.maxDepth = math.max(agg.maxDepth, md)
    if cfg.PERSEED then print("seed", seed, "retrocesos guia", bt, "max seguidos", md, guide and "ok" or "FALLA") end
    if not guide then agg.guideFail += 1
    else
      local stats = {}
      local X, Z, S, H, ok, why = genRoute(cfg, guide, segments*256/STEP, stats)
      agg.time += os.clock() - t0
      if why == "stuck" then agg.routeStuck += 1 end
      if not ok and why ~= "stuck" then agg.routeShort += 1 end
      agg.lastResort += stats.lastResort or 0
      agg.rollbacks += stats.rollbacks or 0; agg.pops += stats.pops or 0; agg.maxPops = math.max(agg.maxPops, stats.maxPops or 0)
      for a, c in stats.attemptHist or {} do agg.attempts[a] = (agg.attempts[a] or 0) + c; agg.pieces += c end
      agg.sharp += stats.kinds.sharp or 0
      agg.hair += (stats.kinds.hairpin or 0) * 2
      local viol, minDist, maxR = verify(cfg, X, Z, S)
      agg.viol += viol; if viol > 0 then agg.violSeeds += 1 end
      agg.minDist = math.min(agg.minDist, minDist); agg.maxR = math.max(agg.maxR, maxR)
      local total, netBig, cumBig, maxNet, nq = rallyMetrics(H)
      agg.windows += total; agg.netBig += netBig; agg.cumBig += cumBig; agg.maxNet = math.max(agg.maxNet, maxNet)
      if netBig > 0 then agg.seedsNet180 += 1 end
      if nq == 4 then agg.seedsQuad4 += 1 end
      agg.km += S[#S] / 1000
    end
  end
  local done = seeds - agg.guideFail
  print(string.format("[%s] semillas=%d guideFail=%d routeStuck=%d routeShort=%d | retrocesos guia=%d (max seguidos %d) | ultimo recurso=%d de %d piezas (1er intento %.0f%%)",
    label, seeds, agg.guideFail, agg.routeStuck, agg.routeShort, agg.backtracks, agg.maxDepth, agg.lastResort, agg.pieces,
    100*(agg.attempts[1] or 0)/math.max(1,agg.pieces)))
  print(string.format("    antiCruce: violaciones=%d (semillas %d) distMin(no vecinas)=%.0f | maxRadio=%.0f | giro>180 neto %.0f%% de ventanas, acumulado %.0f%%, max neto %.0f deg | semillas con ventana neta>180: %d/%d | 4 cuadrantes %d/%d",
    agg.viol, agg.violSeeds, agg.minDist, agg.maxR, 100*agg.netBig/math.max(1,agg.windows), 100*agg.cumBig/math.max(1,agg.windows), deg(agg.maxNet),
    agg.seedsNet180, done, agg.seedsQuad4, done))
  print(string.format("    por km: curvas cerradas %.2f, horquillas %.2f | km por semilla %.0f | tiempo %.1f s por semilla (%.2f s por 100 tramos)",
    agg.sharp/math.max(1,agg.km), agg.hair/math.max(1,agg.km), agg.km/math.max(1,done), agg.time/math.max(1,done),
    agg.time/math.max(1,done)/segments*100))
  local hist = {}
  for a = 1, 6 do hist[#hist+1] = tostring(agg.attempts[a] or 0) end
  print("    intentos usados (1..6): " .. table.concat(hist, " ") .. string.format("  retrocesos de ruta=%d (piezas retiradas %d, maximo de una vez %d)", agg.rollbacks, agg.pops, agg.maxPops))
end

return {runConfig = runConfig, BASE = BASE}
